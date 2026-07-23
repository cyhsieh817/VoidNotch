//
//  VoidNotchApp.swift — @main 進入點
//
//  ⚠️ Xcode app target 專屬。
//  組裝：資料層(已驗證) → @Observable 包裝 → widget 註冊 → NotchShell(DynamicNotchKit) → 狀態列控制展開/收合。
//

import SwiftUI
import AppKit
import AVFoundation
import VoidNotchKit
import SystemMonitor

@main
struct VoidNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 純瀏海 app，無主視窗；設定入口與 dashboard 展開由狀態列選單開啟。
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let peonAudioPreferenceKey = "VoidNotch.notifications.peonAudioEnabled"

    private let systemMonitor = ObservableSystemMonitor()
    private let tokenStore = TokenStore(
        usageProvider: CodexBarTokenUsageProvider(),
        accountManager: CodexBarTokenAccountManager())
    private let agentActivityStore = AgentActivityStore(activityProvider: PeonPingAgentActivityProvider())
    let launchdScheduleStore = LaunchdScheduleStore()
    private let updateCheckStore: UpdateCheckStore = {
        let defaultEndpoint = VoidNotchLinks.updateEndpoint
        let endpointString = ProcessInfo.processInfo.environment["VOIDNOTCH_UPDATE_API"]
        let endpoint = endpointString.flatMap { URL(string: $0) } ?? defaultEndpoint
        // `swift run` / `swift build` 直跑的裸執行檔沒有 Info.plist，取不到
        // CFBundleShortVersionString 時不可 fallback "0.0.0"（否則任何遠端版都變「較新」）。
        // 改傳 isEnabled: false 停用更新檢查；currentVersion "0.0.0" 僅為佔位。
        if let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return UpdateCheckStore(
                client: UpdateCheckClient(endpoint: endpoint),
                currentVersion: currentVersion)
        }
        return UpdateCheckStore(
            client: UpdateCheckClient(endpoint: endpoint),
            currentVersion: "0.0.0",
            isEnabled: false)
    }()
    private lazy var gaugeController = GaugeController(
        systemMonitor: systemMonitor,
        tokenStore: tokenStore,
        agentStore: agentActivityStore)
    private let registry = WidgetRegistry()
    private let peonSoundPlayer = PeonSoundPlayer()
    private let speechPlayer = AgentSpeechPlayer()
    private let soundGate = PeonSoundGate()
    private lazy var hookInstaller = HookInstaller(
        adapters: [
            ClaudeHookAdapter(fs: RealFS()),
            CodexHookAdapter(fs: RealFS()),
            GrokHookAdapter(fs: RealFS()),
            PiHookAdapter(fs: RealFS()),
            HermesHookAdapter(fs: RealFS()),
        ],
        paths: Self.hookPaths(),
        clock: { Date() })
    private lazy var hookWiringStore = HookWiringStore(installer: hookInstaller)

    private var shell: NotchShell?
    private var statusItem: NSStatusItem?
    /// metrics 模式的 hosting view；選集變更時重算寬度用。
    private var menubarMetricsHost: NSHostingView<MenubarSummaryView>?
    private var providerSettingsWindow: NSWindow?
    private var currentLanguage = AppLanguage.resolve(
        UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
    private var currentMenubarMode: MenubarDisplayMode?
    /// 上次套用的 menubar 選集；用來在 defaults 雜訊中只對真變更反應。
    private var currentMenubarItems: [DisplayItem] = []
    private var languageObserver: NSObjectProtocol?

    private var l10n: L10n { L10n(currentLanguage) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AgentBrokerCapabilities.announce()
        republishBrokerCapabilities()
        Task { await updateCheckStore.checkIfDue() }

        registerDefaultPreferences()
        observeUserDefaultsChanges()

        // 1. 啟動已驗證的系統監控輪詢（2 秒）
        systemMonitor.start(interval: 2.0)
        Task { await tokenStore.refreshAccountCatalog() }
        tokenStore.startPolling(interval: 300)
        launchdScheduleStore.startPolling(interval: 120)

        // 2. 註冊 widget（system 偏左、AI 摘要偏右；agent compact 狀態併入 AI 摘要點）
        registry.register(SystemWidget(monitor: systemMonitor))
        registry.register(TokenWidget(store: tokenStore, agentStore: agentActivityStore))
        registry.register(AgentActivityWidget(store: agentActivityStore, connections: { [weak self] in
            guard let self else { return [] }
            // 每次展開時重新偵測：使用者可能剛在別處裝好 hook，面板不該還顯示舊狀態。
            self.hookWiringStore.refresh()
            return AgentConnectionDiagnostics.states(from: self.hookWiringStore.states)
        }))
        registry.register(LaunchdScheduleWidget(store: launchdScheduleStore))

        // 3. 建外殼 → compact 左右側由使用者設定控制
        let speechPlayer = self.speechPlayer
        let shell = NotchShell(
            registry: registry,
            openSettings: { [weak self] in self?.openTokenProviderSettings() },
            onActivityLevelChange: { [weak self] level in self?.systemMonitor.setActivityLevel(level) },
            onSpeechStart: { speechPlayer.stopSpeaking() })
        self.shell = shell
        Task {
            await shell.start()
            agentActivityStore.startPolling(interval: 2) { [weak self] event in
                guard let self else { return }
                self.shell?.presentAgentAlert(event)          // 畫面：不節流
                if self.soundGate.shouldPlay(status: event.status, at: Date()) {
                    self.peonSoundPlayer.play(for: event)     // 聲音：過閘
                }
                self.speechPlayer.speak(for: event)           // TTS：依設定朗讀安全的事件文案
            }
        }

        installStatusItem()

        // 首啟偵測：有未接通/衝突的 agent 才提示，且 24 小時內按過「稍後」就不再打擾。
        Task { @MainActor in
            let states = self.hookInstaller.detectAll(fs: RealFS())
            let pending = states.filter { entry in
                switch entry.value {
                case .notInstalled, .conflict: return true
                case .installed, .agentAbsent: return false
                }
            }
            if !pending.isEmpty, !Self.hookPromptDeferred() {
                self.shell?.presentHookWiringPrompt(pendingCount: pending.count) { [weak self] in
                    self?.runHookInstall(states: states)
                }
            }
        }

        gaugeController.applyEnabledState()
    }

    func republishBrokerCapabilities() {
        AgentBrokerCapabilities.announce()
    }

    static func hookPromptDeferred() -> Bool {
        guard let until = UserDefaults.standard.object(forKey: "VoidNotch.hooks.deferredUntil") as? Date
        else { return false }
        return until > Date()
    }

    func runHookInstall(states: [AgentActivityProviderKind: HookStatus]) {
        let rawResults = hookInstaller.installAll(states: states)
        // 重跑 detectAll 刷新 UI（spec §5.2）：像 Grok 這類空 plan（純鏡射 Claude）的 adapter，
        // installAll 回報 success 不代表真的接通，必須用偵測結果把關，才不會誤報「已接通」。
        hookWiringStore.refresh()
        let results = Self.reconcile(rawResults, with: hookWiringStore.states)
        if results.contains(where: { $0.success }) {
            UserDefaults.standard.set(true, forKey: NotchWidgetPreferenceKey.enabled("agent-activity"))
            // 語音歸屬：VoidNotch 獨佔 → 關 peon.sh（移除已在 ClaudeAdapter 完成）；App 自播開啟
            UserDefaults.standard.set(true, forKey: AppDelegate.peonAudioPreferenceKey)
        }
        shell?.presentHookInstallResults(results)
    }

    /// 設定頁「接線」單一 agent：沿用當前偵測到的實際狀態（notInstalled 或 conflict 皆可），
    /// 而非硬編 .notInstalled，讓衝突情況也能走同一條 installAll 落地路徑。
    private func rewireHook(_ kind: AgentActivityProviderKind) {
        // hookWiringStore.rewire() 內部已在 installAll 後呼叫 refresh()（detectAll），
        // 這裡直接沿用它偵測到的最新狀態把關結果，不重覆多跑一次 detectAll。
        let rawResults = hookWiringStore.rewire(kind)
        let results = Self.reconcile(rawResults, with: hookWiringStore.states)
        if results.contains(where: { $0.success }) {
            UserDefaults.standard.set(true, forKey: NotchWidgetPreferenceKey.enabled("agent-activity"))
            UserDefaults.standard.set(true, forKey: AppDelegate.peonAudioPreferenceKey)
        }
        shell?.presentHookInstallResults(results)
    }

    /// onUnwire 為後續增強（brief §10 YAGNI）：不做破壞性反向操作，僅告知使用者。
    private func unwireHookStub(_ kind: AgentActivityProviderKind) {
        shell?.presentHookInstallResults([
            InstallResult(kind: kind, success: false, message: l10n.hookUnwireComingSoon)
        ])
    }

    private func registerDefaultPreferences() {
        UserDefaults.standard.register(defaults: [
            NotchCompactPreferenceKey.leadingPinned: true,
            NotchCompactPreferenceKey.trailingPinned: false,
            NotchCompactPreferenceKey.leadingMaxWidth: Double(NotchCompactLayout.defaultLeadingWidth),
            NotchCompactPreferenceKey.trailingMaxWidth: Double(NotchCompactLayout.defaultTrailingWidth),
            NotchCompactPreferenceKey.contentHeight: Double(NotchCompactLayout.defaultHeight),
            Self.peonAudioPreferenceKey: true,
        ])
        SystemMetricPreferences.registerDefaults()
        DisplaySelectionStore.registerDefaults()
        UserDefaults.standard.register(defaults: ["VoidNotch.gauge.skin": "seven-segment"])
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemMonitor.stop()
        tokenStore.stopPolling()
        launchdScheduleStore.stopPolling()
        agentActivityStore.stopPolling()
        shell?.stop()
        speechPlayer.stopSpeaking()
        gaugeController.hide()
    }

    private func installStatusItem() {
        applyMenubarMode(MenubarDisplayMode.resolve())
    }

    /// 依模式建立／拆除 statusItem。`off` 不佔 menubar；`icon` 為 brain 圖示；`metrics` 內嵌活體摘要。
    private func applyMenubarMode(_ mode: MenubarDisplayMode) {
        removeStatusItem()
        currentMenubarMode = mode

        switch mode {
        case .off:
            currentMenubarItems = []
            return

        case .icon:
            currentMenubarItems = []
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(
                systemSymbolName: "brain.head.profile",
                accessibilityDescription: "VoidNotch")
            item.button?.imagePosition = .imageOnly
            item.menu = buildStatusMenu()
            statusItem = item

        case .metrics:
            // 空 title/image 時 variableLength 可能壓成 0，改以 hosting 內容固有寬度當 item 長度。
            let host = NSHostingView(rootView: MenubarSummaryView(
                systemMonitor: systemMonitor,
                tokenStore: tokenStore,
                agentStore: agentActivityStore))
            host.sizingOptions = [.intrinsicContentSize]
            let fitted = host.fittingSize
            let width = max(fitted.width, 1)
            let height = max(fitted.height, 18)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)

            let item = NSStatusBar.system.statusItem(withLength: width)
            if let button = item.button {
                button.image = nil
                button.title = ""
                button.addSubview(host)
            }
            // 保留既有選單：點擊仍可開 Settings / Quit 等。
            item.menu = buildStatusMenu()
            statusItem = item
            menubarMetricsHost = host
            currentMenubarItems = DisplaySelectionStore.items(for: .menubar)
        }
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        menubarMetricsHost = nil
    }

    /// 以目前選集量測 metrics 摘要固有寬度（離屏 hosting，不碰現有 statusItem）。
    private func measureMenubarMetricsWidth() -> CGFloat {
        let host = NSHostingView(rootView: MenubarSummaryView(
            systemMonitor: systemMonitor,
            tokenStore: tokenStore,
            agentStore: agentActivityStore))
        host.sizingOptions = [.intrinsicContentSize]
        return max(host.fittingSize.width, 1)
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: l10n.menuSettings, action: #selector(openTokenProviderSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: l10n.menuShowDashboard, action: #selector(showDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: l10n.menuCollapse, action: #selector(tuckIntoNotch), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: l10n.menuToggleGauge, action: #selector(toggleGauge), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: l10n.menuRefreshTokens, action: #selector(refreshTokenUsage), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: l10n.menuRefreshAgents, action: #selector(refreshAgentActivity), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: l10n.menuQuit, action: #selector(quitVoidNotch), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    /// 語言／menubar 模式等 UserDefaults 變更 → 重建 AppKit 側狀態列與視窗標題。
    /// SwiftUI view 各自透過 @AppStorage 反應，這裡只補 statusItem。
    private func observeUserDefaultsChanges() {
        languageObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncLanguageIfNeeded()
                self?.syncMenubarModeIfNeeded()
                self?.syncMenubarMetricsSizeIfNeeded()
                self?.gaugeController.applyEnabledState()
            }
        }
    }

    private func syncLanguageIfNeeded() {
        let language = AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
        guard language != currentLanguage else { return }
        currentLanguage = language
        statusItem?.menu = buildStatusMenu()
        providerSettingsWindow?.title = l10n.settingsWindowTitle
    }

    private func syncMenubarModeIfNeeded() {
        let mode = MenubarDisplayMode.resolve()
        guard mode != currentMenubarMode else { return }
        applyMenubarMode(mode)
    }

    /// menubar 選集變更時重算 statusItem 寬度；僅在寬度真的變了才更新（idempotent）。
    private func syncMenubarMetricsSizeIfNeeded() {
        guard currentMenubarMode == .metrics else { return }
        let latest = DisplaySelectionStore.items(for: .menubar)
        guard latest != currentMenubarItems else { return }

        let newWidth = measureMenubarMetricsWidth()
        let currentWidth = statusItem?.length ?? 0

        // 寬度未變：只同步選集快取與 host 內容，不重建 statusItem。
        if newWidth == currentWidth {
            currentMenubarItems = latest
            if let host = menubarMetricsHost {
                host.rootView = MenubarSummaryView(
                    systemMonitor: systemMonitor,
                    tokenStore: tokenStore,
                    agentStore: agentActivityStore)
            }
            return
        }

        // 寬度變了：就地更新 length + host frame，避免無條件拆除重建造成閃爍。
        currentMenubarItems = latest
        guard let statusItem, let host = menubarMetricsHost else {
            applyMenubarMode(.metrics)
            return
        }
        host.rootView = MenubarSummaryView(
            systemMonitor: systemMonitor,
            tokenStore: tokenStore,
            agentStore: agentActivityStore)
        host.invalidateIntrinsicContentSize()
        let height = max(host.fittingSize.height, 18)
        statusItem.length = newWidth
        host.frame = NSRect(x: 0, y: 0, width: newWidth, height: height)
    }

    @objc private func openTokenProviderSettings() {
        if let providerSettingsWindow {
            providerSettingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsMetrics.windowWidth,
                height: SettingsMetrics.minWindowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = l10n.settingsWindowTitle
        providerSettingsWindow = window
        window.contentViewController = NSHostingController(rootView: ProviderSettingsView(
            store: tokenStore,
            registry: registry,
            hookWiringStore: hookWiringStore,
            onRewireHook: { [weak self] kind in self?.rewireHook(kind) },
            onUnwireHook: { [weak self] kind in self?.unwireHookStub(kind) },
            onResetGaugePosition: { [weak self] in self?.gaugeController.resetPosition() },
            onPreviewSound: { [weak self] category in self?.peonSoundPlayer.preview(category: category) },
            onPreviewSpeech: { [weak self] language in self?.speechPlayer.preview(language: language) },
            launchdScheduleStore: launchdScheduleStore,
            updateCheckStore: updateCheckStore,
            onContentHeightChange: { [weak self] height in
                self?.resizeSettingsWindow(toContentHeight: height)
            }))
        // NSHostingController 掛上時 SwiftUI 初始 fitting size 可能為 0；若後續高度 preference 回呼因競態未觸發，視窗會永久卡在 0×0 隱形。初始尺寸必須決定性設定，preference 只負責精修高度。
        window.setContentSize(NSSize(width: SettingsMetrics.windowWidth, height: SettingsMetrics.minWindowHeight))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resizeSettingsWindow(toContentHeight contentHeight: CGFloat) {
        guard let window = providerSettingsWindow else { return }

        let clampedHeight = min(
            max(contentHeight, SettingsMetrics.minWindowHeight),
            SettingsMetrics.maxWindowHeight)
        let currentContentHeight = window.contentRect(forFrameRect: window.frame).height
        guard abs(clampedHeight - currentContentHeight) >= 1 else { return }

        let oldFrame = window.frame
        let targetContentRect = NSRect(
            x: 0,
            y: 0,
            width: SettingsMetrics.windowWidth,
            height: clampedHeight)
        let newFrameHeight = window.frameRect(forContentRect: targetContentRect).height
        let newFrame = NSRect(
            x: oldFrame.origin.x,
            y: oldFrame.maxY - newFrameHeight,
            width: oldFrame.width,
            height: newFrameHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = .init(name: .easeOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    @objc private func showDashboard() {
        Task { await shell?.expand() }
    }

    @objc private func tuckIntoNotch() {
        Task { await shell?.compact() }
    }

    @objc private func toggleGauge() {
        let defaults = UserDefaults.standard
        let enabled = !defaults.bool(forKey: "VoidNotch.gauge.enabled")
        defaults.set(enabled, forKey: "VoidNotch.gauge.enabled")
        gaugeController.applyEnabledState()
    }

    @objc private func refreshTokenUsage() {
        Task { await tokenStore.refresh() }
    }

    @objc private func refreshAgentActivity() {
        Task { await agentActivityStore.refresh() }
    }

    @objc private func quitVoidNotch() {
        NSApp.terminate(nil)
    }
}

struct RealFS: FileSystemReading {
    func fileExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func readData(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}

extension AppDelegate {
    /// 安裝回報以「重新偵測」把關（spec §5.2「重跑 detectAll() 刷新 UI」）：
    /// Grok 的 plan() 回空陣列（純鏡射 Claude 的 settings.json），installAll 對空 plan 一律回報
    /// success，但那不代表 Grok 真的接通——只有 Claude 也一併接通時，Grok 的 detect 才會是
    /// .installed。若逐一結果宣稱成功、但事後偵測未確認，這裡降級為失敗並附上原因，
    /// 讓「✓ 已接通」的清單只列出偵測證實的 agent，不誤報。
    static func reconcile(
        _ results: [InstallResult], with detectedStates: [AgentActivityProviderKind: HookStatus]
    ) -> [InstallResult] {
        let message = L10n(AppLanguage.resolve(
            UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))).hookVerifyFailed
        return results.map { result in
            guard result.success, detectedStates[result.kind] != .installed else { return result }
            return InstallResult(
                kind: result.kind,
                success: false,
                message: message)
        }
    }

    static func hookPaths() -> HookPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        let hooksDir = appSupport.appendingPathComponent("VoidNotch/hooks", isDirectory: true)
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("hooks") ?? hooksDir
        return HookPaths(
            home: home,
            appSupportHooks: hooksDir,
            bundledRelay: bundled.appendingPathComponent("peonping-voidnotch-relay.sh"),
            bundledPiExtension: bundled.appendingPathComponent("voidnotch.ts"))
    }
}

/// Agent 事件 TTS：AVSpeechSynthesizer + AgentSpeechPreferences / AgentSpeechMessage。
@MainActor
final class AgentSpeechPlayer {
    private let synthesizer = AVSpeechSynthesizer()
    private let preferences: AgentSpeechPreferences

    init(userDefaults: UserDefaults = .standard) {
        preferences = AgentSpeechPreferences(userDefaults: userDefaults)
    }

    func speak(for event: AgentActivityEvent) {
        guard preferences.speaks(event.status),
              let message = AgentSpeechMessage.event(for: event)
        else { return }
        speak(text: message.text, language: message.language)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func preview(language: AgentSpeechLanguage) {
        let text: String
        switch language {
        case .zhTW:
            text = "VoidNotch 中文語音測試"
        case .enUS:
            text = "VoidNotch English voice preview"
        }
        speak(text: text, language: language)
    }

    private func speak(text: String, language: AgentSpeechLanguage) {
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Float(preferences.rate)
        utterance.voice = resolveVoice(for: language)
        synthesizer.speak(utterance)
    }

    private func resolveVoice(for language: AgentSpeechLanguage) -> AVSpeechSynthesisVoice? {
        let preferredIdentifier: String?
        switch language {
        case .zhTW:
            preferredIdentifier = preferences.chineseVoiceIdentifier
        case .enUS:
            preferredIdentifier = preferences.englishVoiceIdentifier
        }

        if let preferredIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: preferredIdentifier)
        {
            return voice
        }
        return AVSpeechSynthesisVoice(language: language.languageCode)
    }
}

@MainActor
private final class PeonSoundPlayer {
    private let pack: PeonSoundPack
    private let preferences: AlertSoundPreferences
    private let userDefaults: UserDefaults
    private var currentSound: NSSound?
    private var lastPlayedFileByCategory: [String: String] = [:]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard)
    {
        pack = PeonSoundPack(environment: environment, fileManager: fileManager)
        preferences = AlertSoundPreferences(userDefaults: userDefaults, fileManager: fileManager)
        self.userDefaults = userDefaults
    }

    func play(for event: AgentActivityEvent) {
        guard userDefaults.object(forKey: AppDelegate.peonAudioPreferenceKey) as? Bool ?? true,
              let category = AlertSoundCategory(status: event.status)
        else { return }

        playSelection(for: category)
    }

    func preview(category: AlertSoundCategory) {
        currentSound?.stop()
        currentSound = nil
        playSelection(for: category)
    }

    private func playSelection(for category: AlertSoundCategory) {
        let selection = preferences.selection(for: category)
        switch selection.kind {
        case .soundPack:
            playSoundPack(for: category)
        case .system:
            guard let name = selection.value,
                  AlertSoundPreferences.systemSoundNames.contains(name),
                  let sound = NSSound(named: NSSound.Name(name))
            else {
                playSoundPack(for: category)
                return
            }
            play(sound)
        case .localFile:
            guard let soundURL = preferences.resolvedLocalFileURL(for: category),
                  let sound = NSSound(contentsOf: soundURL, byReference: true)
            else {
                playSoundPack(for: category)
                return
            }
            play(sound)
        }
    }

    private func playSoundPack(for category: AlertSoundCategory) {
        let categoryName = category.packCategoryName
        guard let candidates = pack.manifest?.categories[categoryName]?.sounds,
              !candidates.isEmpty
        else { return }

        let alternatives = candidates.filter { $0.file != lastPlayedFileByCategory[categoryName] }
        guard let selected = (alternatives.isEmpty ? candidates : alternatives).randomElement(),
              let soundURL = pack.validatedSoundURL(for: selected.file),
              let sound = NSSound(contentsOf: soundURL, byReference: true)
        else { return }

        lastPlayedFileByCategory[categoryName] = selected.file
        play(sound)
    }

    private func play(_ sound: NSSound) {
        currentSound?.stop()
        currentSound = sound
        sound.play()
    }
}
