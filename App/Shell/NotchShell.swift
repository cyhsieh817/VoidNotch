//
//  NotchShell.swift — DynamicNotchKit 薄封裝（整合接縫）
//
//  ⚠️ Xcode app target 專屬，依賴 SPM 套件 DynamicNotchKit（main）。
//  API 已於 dynamicnotchkit-spike §1 逐參數驗證；compact 兩側可各自常開或縮入劉海。
//
//  三層解耦的接縫：外殼(DynamicNotchKit) ← 餵入 ← 註冊表(WidgetRegistry) ← 消費 ← 資料層。
//

import SwiftUI
import AppKit
import DynamicNotchKit
import SystemMonitor
import VoidNotchKit

@MainActor
public final class NotchShell {
    private static var currentL10n: L10n {
        L10n(AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)))
    }

    private let registry: WidgetRegistry
    private let openSettings: (@MainActor () -> Void)?
    private let onActivityLevelChange: (@MainActor (MonitorActivityLevel) -> Void)?
    private let onSpeechStart: (@MainActor () -> Void)?
    private let isProProvider: @MainActor @Sendable () -> Bool
    private var notch: DynamicNotch<AnyView, AnyView, AnyView>?
    private var autoPresentationTask: Task<Void, Never>?
    private var agentAlertTask: Task<Void, Never>?
    private var agentAlertCollapseTask: Task<Void, Never>?
    private var agentAlertGeneration: UInt64 = 0
    private let agentAlertState = NotchAgentAlertState()
    private let optionSpeechRecognizer = AgentOptionSpeechRecognizer()
    private let proUpsellState = NotchProUpsellState()
    private var hookBannerTask: Task<Void, Never>?
    private var hookBannerGeneration: UInt64 = 0
    private let hookBannerState = NotchHookBannerState()
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var reduceMotionObserver: (any NSObjectProtocol)?
    private var presentation: NotchPresentation = .hidden
    private var isTransitioning = false
    private var pendingPresentation: NotchPresentation?
    private var transitionDriverTask: Task<Void, Never>?
    private var presentationChangedAt = Date.distantPast
    private var leadingContentWidth: CGFloat = 116
    private var mouseOverNotchArea = false
    private var agentAlertFrame: CGRect?
    /// 已彈出、但使用者尚未作答的問答請求。relay 正在另一端等它，收掉卡片前必須先放行。
    private var pendingInputRequest: AgentInputRequest?
    /// 待答卡 FIFO；只存已通過 Pro gate 且 request_id 尚未處理的請求。
    private var queuedInputEvents: [AgentActivityEvent] = []
    private var queuedInputRequestIDs = Set<UUID>()

    /// 一般提醒卡的生命週期；同一時間只允許一張卡片可見。
    private static let standardAgentAlertLifetime: TimeInterval = 30
    /// 問答卡的存活期，且必須明顯短於 relay 的 broker timeout（590 秒），
    /// 逾時才來得及送出 dismissal 讓 agent 回終端機提問。
    private static let inputRequestAlertLifetime: TimeInterval = 300

    public init(registry: WidgetRegistry,
                openSettings: (@MainActor () -> Void)? = nil,
                onActivityLevelChange: (@MainActor (MonitorActivityLevel) -> Void)? = nil,
                onSpeechStart: (@MainActor () -> Void)? = nil,
                isProProvider: @escaping @MainActor @Sendable () -> Bool = { false }) {
        self.registry = registry
        self.openSettings = openSettings
        self.onActivityLevelChange = onActivityLevelChange
        self.onSpeechStart = onSpeechStart
        self.isProProvider = isProProvider
    }

    /// 建立瀏海面板。收合時依使用者設定顯示左側/右側，縮起側不在實體瀏海外側殘留。
    public func start() async {
        AgentBrokerCapabilities.announce(isPro: isProProvider())

        let notch = DynamicNotch<AnyView, AnyView, AnyView>(
            hoverBehavior: [.keepVisible, .increaseShadow], // 展開期間 hover 不消失（spike §1）
            style: .auto,
            expanded: { [registry, agentAlertState, proUpsellState, hookBannerState, optionSpeechRecognizer, onSpeechStart, weak self] in
                let screen = self?.activeScreen() ?? NSScreen.main ?? NSScreen()
                let menuBar = self?.menuBarHeight(on: screen) ?? 37
                let topInset = NotchMetrics.expandedTopInset(menuBarHeight: menuBar)
                let scrollMaxH = NotchMetrics.expandedScrollMaxHeight(screenFrameHeight: screen.frame.height)
                return AnyView(
                    NotchExpandedContent(
                        registry: registry,
                        agentAlertState: agentAlertState,
                        proUpsellState: proUpsellState,
                        hookBannerState: hookBannerState,
                        topInset: topInset,
                        scrollMaxHeight: scrollMaxH,
                        speechRecognizer: optionSpeechRecognizer,
                        onSpeechStart: onSpeechStart ?? {},
                        onAgentAlertFrameChange: { frame in
                            self?.updateAgentAlertFrame(frame)
                        })
                )
            },
            compactLeading: { [registry, weak self] in
                AnyView(NotchCompactSlotView(side: .leading, registry: registry, onWidth: { w in
                    Task { @MainActor in self?.leadingContentWidth = max(w, 1) }
                }))
            },
            compactTrailing: { [registry] in AnyView(NotchCompactSlotView(side: .trailing, registry: registry)) }
        )
        self.notch = notch
        applyTransitionConfiguration()
        observeReduceMotionChanges()

        // 啟動時進入 compact；縮起側由 slot 設定收進實體劉海。
        await transition(to: .compact)
        startAutoPresentation()
        installMouseMonitors()
    }

    /// 系統「減少動態效果」開啟時，改用短促、無回彈的曲線。
    /// 減少動態 ≠ 零動畫：硬切同樣會失去方向感，這裡只拿掉 overshoot 與彈性尾勁。
    private static func transitionConfiguration(
        reduceMotion: Bool
    ) -> DynamicNotchTransitionConfiguration {
        if reduceMotion {
            return DynamicNotchTransitionConfiguration(
                openingAnimation: .easeOut(duration: 0.15),
                closingAnimation: .easeOut(duration: 0.15),
                conversionAnimation: .easeOut(duration: 0.15),
                skipIntermediateHides: true)
        }
        return DynamicNotchTransitionConfiguration(
            openingAnimation: .bouncy(duration: 0.42),
            closingAnimation: .smooth(duration: 0.32),
            conversionAnimation: .snappy(duration: 0.4),
            skipIntermediateHides: true)
    }

    private static var systemReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func applyTransitionConfiguration() {
        notch?.transitionConfiguration = Self.transitionConfiguration(
            reduceMotion: Self.systemReduceMotion)
    }

    private func observeReduceMotionChanges() {
        if let reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
        }
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTransitionConfiguration() }
        }
    }

    public func expand() async { await transition(to: .expanded) }
    public func compact() async { await transition(to: .compact) }
    public func hide() async { await transition(to: .hidden) }
    public func presentAgentAlert(_ event: AgentActivityEvent) {
        if let inputRequest = event.inputRequest, !isProProvider() {
            // Community／空 capabilities 不可代答；只放行這一筆，不讓它變成可作答 UI。
            try? AgentInputResponseWriter.dismiss(request: inputRequest)
            guard pendingInputRequest == nil else { return }
            var notifyOnlyEvent = event
            notifyOnlyEvent.inputRequest = nil
            presentOrdinaryAgentAlert(notifyOnlyEvent, showProUpsell: true)
            return
        }

        if let inputRequest = event.inputRequest {
            guard !isKnownInputRequest(inputRequest.requestID) else { return }
            if pendingInputRequest != nil || agentAlertState.event?.inputRequest != nil {
                queuedInputEvents.append(event)
                queuedInputRequestIDs.insert(inputRequest.requestID)
                return
            }
            // 可作答卡片是最高優先級，立即取代任何一般提醒。
            proUpsellState.isVisible = false
            displayAgentAlert(event)
            return
        }

        presentOrdinaryAgentAlert(event)
    }

    private func presentOrdinaryAgentAlert(
        _ event: AgentActivityEvent,
        showProUpsell: Bool = false)
    {
        // 待答卡是使用者互動狀態；普通提醒只能留在活動紀錄，不得覆蓋或 dismiss 它。
        guard pendingInputRequest == nil else { return }
        if let current = agentAlertState.event {
            guard current.inputRequest == nil,
                  event.status.alertPriority > current.status.alertPriority
            else { return }
        }
        proUpsellState.isVisible = showProUpsell
        displayAgentAlert(event)
    }

    private func displayAgentAlert(_ event: AgentActivityEvent) {
        agentAlertCollapseTask?.cancel()
        agentAlertCollapseTask = nil
        agentAlertTask?.cancel()
        agentAlertTask = nil
        agentAlertGeneration &+= 1
        let generation = agentAlertGeneration
        let now = Date()
        let answerableInputRequest = event.inputRequest
        let deadline: Date
        if let answerableInputRequest {
            // 問答卡不與一般 30 秒提醒共用生命週期；relay 仍在另一端等待答案，給它自己的存活期。
            deadline = now.addingTimeInterval(Self.inputRequestAlertLifetime)
            pendingInputRequest = answerableInputRequest
            // 人不在螢幕前會直接錯過瀏海卡片；鏡射一則系統通知（受偏好開關與授權狀態閘門，內容只含
            // provider 與 title／header 摘要，見 AgentAlertNotificationMirror 的隱私邊界註解）。
            AgentAlertNotificationMirror.shared.postInputRequestNotification(
                provider: event.provider.displayName,
                title: event.title,
                questionSummary: answerableInputRequest.questions.first?.header)
        } else {
            deadline = now.addingTimeInterval(Self.standardAgentAlertLifetime)
        }
        agentAlertState.event = event
        if answerableInputRequest != nil {
            let navigationTarget = event.navigation
            agentAlertState.submit = { [weak self, navigationTarget] request, selections in
                guard let self else { return nil }
                // 第二道獨立驗簽點（使用時重驗）：卡片顯示期間授權可能已過期／被撤銷，
                // 寫出答案前必須再驗一次，不能只信賴 presentAgentAlert 入口那道判斷
                // （卡片可能已停留數分鐘，期間 trial/簽章可能過期）。
                guard self.isProProvider() else {
                    try? AgentInputResponseWriter.dismiss(request: request)
                    guard self.pendingInputRequest?.requestID == request.requestID else { return nil }
                    let sourceEvent = self.agentAlertState.event
                    self.pendingInputRequest = nil
                    self.finishCurrentAgentAlert(releaseCurrentInput: false)
                    if var notifyOnlyEvent = sourceEvent {
                        notifyOnlyEvent.inputRequest = nil
                        self.presentOrdinaryAgentAlert(notifyOnlyEvent, showProUpsell: true)
                    }
                    return nil
                }
                do {
                    try AgentInputResponseWriter.write(request: request, selections: selections)
                    // 答案已送出，dismissal 不可再覆寫這個檔案。
                    guard self.agentAlertGeneration == generation,
                          self.pendingInputRequest?.requestID == request.requestID
                    else { return nil }
                    self.pendingInputRequest = nil
                    self.finishCurrentAgentAlert(releaseCurrentInput: false)
                    if let navigationTarget, navigationTarget.isActionable {
                        AgentActivityNavigation.open(navigationTarget)
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        } else {
            agentAlertState.submit = nil
        }

        agentAlertTask = Task { [weak self] in
            guard let self else { return }
            guard await self.transitionAgentAlert(to: .expanded, generation: generation) else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            } catch {
                return
            }
            guard !Task.isCancelled, self.agentAlertGeneration == generation else { return }
            // 走到這裡代表這顆 task 沒被 cancel、generation 沒被 bump：使用者手動作答（submit）
            // 或手動關閉（dismissAgentAlert）都會在事發當下 cancel 掉這顆 task，能撐過 sleep
            // 撐到這裡的只有「逾時未作答」一種情形，才鏡射「已放行回終端機」通知。
            if answerableInputRequest != nil {
                AgentAlertNotificationMirror.shared.postReleasedNotification(provider: event.provider.displayName)
            }
            if self.hookBannerState.content != nil {
                self.finishAgentAlertIfCurrent(generation: generation)
                return
            }
            guard self.agentAlertGeneration == generation else { return }
            self.finishAgentAlertIfCurrent(generation: generation)
        }
    }

    private func isKnownInputRequest(_ requestID: UUID) -> Bool {
        pendingInputRequest?.requestID == requestID
            || queuedInputRequestIDs.contains(requestID)
    }

    private func finishAgentAlertIfCurrent(generation: UInt64) {
        guard agentAlertGeneration == generation else { return }
        finishCurrentAgentAlert(releaseCurrentInput: true)
    }

    private func finishCurrentAgentAlert(releaseCurrentInput: Bool) {
        agentAlertCollapseTask?.cancel()
        agentAlertCollapseTask = nil
        agentAlertTask?.cancel()
        agentAlertTask = nil
        if releaseCurrentInput { releasePendingInputRequest() }
        else { pendingInputRequest = nil }
        agentAlertGeneration &+= 1

        if let next = queuedInputEvents.first {
            queuedInputEvents.removeFirst()
            if let requestID = next.inputRequest?.requestID {
                queuedInputRequestIDs.remove(requestID)
            }
            proUpsellState.isVisible = false
            displayAgentAlert(next)
            return
        }

        let finishingEventID = agentAlertState.event?.id
        let collapseGeneration = agentAlertGeneration
        // 收合動畫期間仍保留 event 供畫面渲染，但先切斷送出入口，避免重複回答。
        agentAlertState.submit = { _, _ in nil }
        proUpsellState.isVisible = false
        agentAlertFrame = nil
        agentAlertCollapseTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.agentAlertGeneration == collapseGeneration,
                   self.agentAlertState.event?.id == finishingEventID
                {
                    self.agentAlertState.event = nil
                    self.agentAlertState.submit = nil
                    self.agentAlertCollapseTask = nil
                }
            }
            guard self.hookBannerState.content == nil else { return }
            await self.transition(to: .compact)
            guard !Task.isCancelled,
                  self.agentAlertGeneration == collapseGeneration,
                  self.agentAlertState.event?.id == finishingEventID
            else { return }

            if let next = self.queuedInputEvents.first {
                self.queuedInputEvents.removeFirst()
                if let requestID = next.inputRequest?.requestID {
                    self.queuedInputRequestIDs.remove(requestID)
                }
                self.agentAlertState.event = nil
                self.agentAlertState.submit = nil
                self.agentAlertCollapseTask = nil
                self.proUpsellState.isVisible = false
                self.displayAgentAlert(next)
                return
            }

            self.agentAlertState.event = nil
            self.agentAlertState.submit = nil
            self.agentAlertCollapseTask = nil
            // 收合期間可能新出現 hook banner；清掉自己的卡片後交還互斥顯示權。
            guard self.hookBannerState.content == nil else { return }
        }
    }

    /// 卡片收掉但沒作答時，通知 relay 放棄接管，讓 agent 立刻回終端機提問。冪等。
    private func releasePendingInputRequest() {
        guard let request = pendingInputRequest else { return }
        pendingInputRequest = nil
        try? AgentInputResponseWriter.dismiss(request: request)
    }

    private func dismissAgentAlert() {
        finishCurrentAgentAlert(releaseCurrentInput: true)
    }

    /// 首啟一鍵接線提示列：「⚡ 可接管 N 個 agent…[啟用][稍後]」。持續展開直到使用者按下其中一個按鈕
    /// （不像 presentAgentAlert 有 3 秒自動收合，因為這裡需要使用者決策）。
    public func presentHookWiringPrompt(pendingCount: Int, onEnable: @escaping () -> Void) {
        let l10n = Self.currentL10n
        let text = l10n.hookPromptBanner(pendingCount)

        hookBannerTask?.cancel()
        hookBannerGeneration &+= 1
        let generation = hookBannerGeneration

        hookBannerState.content = .prompt(
            text: text,
            primaryTitle: l10n.enable,
            onPrimary: { [weak self] in
                self?.dismissHookBanner(generation: generation)
                onEnable()
            },
            secondaryTitle: l10n.later,
            onSecondary: { [weak self] in
                UserDefaults.standard.set(
                    Date().addingTimeInterval(86400),
                    forKey: "VoidNotch.hooks.deferredUntil")
                self?.dismissHookBanner(generation: generation)
            })

        hookBannerTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.transitionHookBanner(to: .expanded, generation: generation)
        }
    }

    /// 安裝結果摘要列：成功/失敗各一句，4 秒後自動收合。無按鈕，純資訊。
    public func presentHookInstallResults(_ results: [InstallResult]) {
        let l10n = Self.currentL10n
        let ok = results.filter { $0.success }.map { $0.kind.displayName }
        let bad = results.filter { !$0.success }
        var text = ok.isEmpty ? "" : "✓ " + ok.joined(separator: " · ") + " " + l10n.hookInstalledSuffix
        if let first = bad.first {
            if !text.isEmpty { text += "  " }
            text += "✗ \(first.kind.displayName)：\(first.message ?? l10n.hookInstallFailedFallback)"
        }
        guard !text.isEmpty else { return }

        hookBannerTask?.cancel()
        hookBannerGeneration &+= 1
        let generation = hookBannerGeneration
        hookBannerState.content = .info(text: text)

        hookBannerTask = Task { [weak self] in
            guard let self else { return }
            guard await self.transitionHookBanner(to: .expanded, generation: generation) else { return }
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard !Task.isCancelled, self.hookBannerGeneration == generation else { return }
            // sibling guard：agent alert 還開著時不強制收合，讓它自己的計時器負責收合。
            guard self.agentAlertState.event == nil else {
                self.hookBannerState.content = nil
                return
            }
            guard await self.transitionHookBanner(to: .compact, generation: generation) else { return }
            self.hookBannerState.content = nil
        }
    }

    private func dismissHookBanner(generation: UInt64) {
        guard hookBannerGeneration == generation else { return }
        hookBannerTask?.cancel()
        hookBannerState.content = nil
        Task { [weak self] in
            guard let self else { return }
            // sibling guard：agent alert 還開著時不強制收合，交由它自己的生命週期收尾。
            guard self.agentAlertState.event == nil else { return }
            await self.transition(to: .compact)
        }
    }

    public func stop() {
        autoPresentationTask?.cancel()
        autoPresentationTask = nil
        agentAlertCollapseTask?.cancel()
        agentAlertCollapseTask = nil
        agentAlertTask?.cancel()
        agentAlertTask = nil
        optionSpeechRecognizer.cancel()
        releasePendingInputRequest()
        for event in queuedInputEvents {
            if let request = event.inputRequest { try? AgentInputResponseWriter.dismiss(request: request) }
        }
        queuedInputEvents.removeAll()
        queuedInputRequestIDs.removeAll()
        agentAlertState.event = nil
        agentAlertState.submit = nil
        proUpsellState.isVisible = false
        agentAlertFrame = nil
        hookBannerTask?.cancel()
        hookBannerTask = nil
        hookBannerState.content = nil
        removeMouseMonitors()
        if let reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
            self.reduceMotionObserver = nil
        }
    }

    private func activeScreen() -> NSScreen {
        NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// 選單列高(含瀏海)= 螢幕 frame 頂 − 可視區頂。無瀏海機型回一般選單列高。
    private func menuBarHeight(on screen: NSScreen) -> CGFloat {
        max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// 瀏海寬度（macOS 12+ auxiliary 區）；無瀏海機型回 0。
    private func notchWidth(on screen: NSScreen) -> CGFloat {
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        if left == 0, right == 0 { return 0 }
        return max(0, screen.frame.width - left - right)
    }

    private func startAutoPresentation() {
        autoPresentationTask?.cancel()
        autoPresentationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 140_000_000)
                self?.updateClickThrough()
                await self?.syncPresentationWithHover()
            }
        }
    }

    /// 依滑鼠位置切換點擊穿透：compact 僅「左側內容 + 瀏海」命中區可互動；
    /// expanded alert 僅實際卡片範圍可互動，其餘 expanded 與 hidden 狀態皆可互動。
    private func updateClickThrough() {
        guard let window = notch?.windowController?.window else { return }
        switch presentation {
        case .expanded where agentAlertState.event != nil:
            let inside = agentAlertFrame?.contains(NSEvent.mouseLocation) ?? false
            mouseOverNotchArea = inside
            setWindow(window, ignoresMouseEvents: !inside)
        case .expanded, .hidden:
            mouseOverNotchArea = true
            setWindow(window, ignoresMouseEvents: false)
        case .compact:
            let inside = compactHitRect().contains(NSEvent.mouseLocation)
            mouseOverNotchArea = inside
            setWindow(window, ignoresMouseEvents: !inside)
        }
    }

    private func setWindow(_ window: NSWindow, ignoresMouseEvents: Bool) {
        guard window.ignoresMouseEvents != ignoresMouseEvents else { return }
        window.ignoresMouseEvents = ignoresMouseEvents
    }

    private func updateAgentAlertFrame(_ frame: CGRect?) {
        guard agentAlertFrame != frame else { return }
        agentAlertFrame = frame
        updateClickThrough()
    }

    /// compact 狀態的命中矩形（左側內容 + 瀏海，右緣止於瀏海右緣）。
    private func compactHitRect() -> CGRect {
        let screen = activeScreen()
        return NotchMetrics.compactPanelRect(
            screenFrame: screen.frame,
            notchWidth: notchWidth(on: screen),
            menuBarHeight: menuBarHeight(on: screen),
            leftContentWidth: leadingContentWidth)
    }

    private func syncPresentationWithHover() async {
        guard let notch, !isTransitioning, agentAlertState.event == nil, hookBannerState.content == nil else { return }

        switch presentation {
        case .compact:
            break
        case .expanded:
            guard !notch.isHovering else { return }
            guard Date().timeIntervalSince(presentationChangedAt) > 0.75 else { return }

            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            guard presentation == .expanded, !isTransitioning, notch.isHovering == false else { return }
            await transition(to: .compact)
        case .hidden:
            break
        }
    }

    private func transition(to nextPresentation: NotchPresentation) async {
        pendingPresentation = nextPresentation
        if let transitionDriverTask {
            await transitionDriverTask.value
            return
        }

        let driver = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainPendingPresentations()
        }
        transitionDriverTask = driver
        await driver.value
    }

    private func drainPendingPresentations() async {
        defer {
            isTransitioning = false
            transitionDriverTask = nil
        }
        guard let notch else {
            pendingPresentation = nil
            return
        }

        while let nextPresentation = pendingPresentation {
            pendingPresentation = nil
            guard presentation != nextPresentation else { continue }
            isTransitioning = true
            switch nextPresentation {
            case .compact:
                await notch.compact()
            case .expanded:
                await notch.expand()
            case .hidden:
                await notch.hide()
            }
            presentation = nextPresentation
            presentationChangedAt = Date()

            switch nextPresentation {
            case .expanded: onActivityLevelChange?(.foreground)
            case .compact:  onActivityLevelChange?(.background)
            case .hidden:   onActivityLevelChange?(.idle)
            }
        }
    }

    private func transitionAgentAlert(
        to nextPresentation: NotchPresentation,
        generation: UInt64) async -> Bool
    {
        guard !Task.isCancelled, agentAlertGeneration == generation else { return false }
        await transition(to: nextPresentation)
        return !Task.isCancelled
            && agentAlertGeneration == generation
            && presentation == nextPresentation
    }

    private func transitionHookBanner(
        to nextPresentation: NotchPresentation,
        generation: UInt64) async -> Bool
    {
        guard !Task.isCancelled, hookBannerGeneration == generation else { return false }
        await transition(to: nextPresentation)
        return !Task.isCancelled && hookBannerGeneration == generation
    }

    // mouseMoved 已由 autoPresentationTask 的 140ms 輪詢取代，避免每事件 actor hop。
    private func installMouseMonitors() {
        removeMouseMonitors()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseDown(event)
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseDown(event)
            }
        }
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard let notch else { return }
        if presentation == .expanded, agentAlertState.event != nil {
            let inside = agentAlertFrame?.contains(NSEvent.mouseLocation) ?? false
            guard inside else {
                dismissAgentAlert()
                return
            }
        }
        guard !isTransitioning else { return }
        let overArea: Bool
        if presentation == .compact {
            overArea = compactHitRect().contains(NSEvent.mouseLocation)
        } else {
            overArea = notch.isHovering
        }
        guard overArea else { return }

        switch event.type {
        case .leftMouseDown where presentation == .compact:
            Task { @MainActor in await transition(to: .expanded) }
        case .rightMouseDown:
            openSettings?()
        default:
            break
        }
    }
}

private struct NotchExpandedContent: View {
    let registry: WidgetRegistry
    @Bindable var agentAlertState: NotchAgentAlertState
    @Bindable var proUpsellState: NotchProUpsellState
    @Bindable var hookBannerState: NotchHookBannerState
    let topInset: CGFloat
    let scrollMaxHeight: CGFloat
    let speechRecognizer: AgentOptionSpeechRecognizer
    let onSpeechStart: () -> Void
    let onAgentAlertFrameChange: (CGRect?) -> Void

    var body: some View {
        Group {
            if let event = agentAlertState.event {
                VStack(spacing: 0) {
                    NotchAgentAlertView(
                        event: event,
                        topInset: topInset,
                        onSubmit: agentAlertState.submit,
                        speechRecognizer: speechRecognizer,
                        onSpeechStart: onSpeechStart,
                        onFrameChange: onAgentAlertFrameChange)
                    if proUpsellState.isVisible {
                        Button(Self.currentL10n.proUpsellAnswerInNotch) {
                            NSWorkspace.shared.open(VoidNotchLinks.site)
                        }
                            .buttonStyle(.borderedProminent)
                            .tint(.yellow)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.bottom, 14)
                    }
                }
                .background {
                    NotchAlertContainerBoundsObserver(onFrameChange: onAgentAlertFrameChange)
                }
                .onDisappear { onAgentAlertFrameChange(nil) }
            } else if let content = hookBannerState.content {
                NotchHookBannerView(content: content, topInset: topInset)
            } else {
                NotchExpandedPanel(
                    registry: registry,
                    topInset: topInset,
                    scrollMaxHeight: scrollMaxHeight)
            }
        }
    }

    private static var currentL10n: L10n {
        L10n(AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)))
    }
}

@MainActor
@Observable
private final class NotchProUpsellState {
    var isVisible = false
}

private struct NotchAlertContainerBoundsObserver: NSViewRepresentable {
    let onFrameChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> BoundsTrackingView {
        BoundsTrackingView(onFrameChange: onFrameChange)
    }

    func updateNSView(_ nsView: BoundsTrackingView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.reportFrame()
    }

    static func dismantleNSView(_ nsView: BoundsTrackingView, coordinator: ()) {
        nsView.onFrameChange(nil)
    }

    @MainActor
    final class BoundsTrackingView: NSView {
        var onFrameChange: (CGRect?) -> Void
        private var lastFrame: CGRect?

        init(onFrameChange: @escaping (CGRect?) -> Void) {
            self.onFrameChange = onFrameChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
        }

        override func layout() {
            super.layout()
            reportFrame()
        }

        func reportFrame() {
            guard let window else {
                publish(nil)
                return
            }
            publish(window.convertToScreen(convert(bounds, to: nil)))
        }

        private func publish(_ frame: CGRect?) {
            guard lastFrame != frame else { return }
            lastFrame = frame
            onFrameChange(frame)
        }
    }
}
