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
    private let registry: WidgetRegistry
    private let openSettings: (@MainActor () -> Void)?
    private let onActivityLevelChange: (@MainActor (MonitorActivityLevel) -> Void)?
    private var notch: DynamicNotch<AnyView, AnyView, AnyView>?
    private var autoPresentationTask: Task<Void, Never>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var presentation: NotchPresentation = .hidden
    private var isTransitioning = false
    private var presentationChangedAt = Date.distantPast
    private var leadingContentWidth: CGFloat = 116
    private var mouseOverNotchArea = false

    public init(registry: WidgetRegistry,
                openSettings: (@MainActor () -> Void)? = nil,
                onActivityLevelChange: (@MainActor (MonitorActivityLevel) -> Void)? = nil) {
        self.registry = registry
        self.openSettings = openSettings
        self.onActivityLevelChange = onActivityLevelChange
    }

    /// 建立瀏海面板。收合時依使用者設定顯示左側/右側，縮起側不在實體瀏海外側殘留。
    public func start() async {
        let notch = DynamicNotch<AnyView, AnyView, AnyView>(
            hoverBehavior: [.keepVisible, .increaseShadow], // 展開期間 hover 不消失（spike §1）
            style: .auto,
            expanded: { [registry, weak self] in
                let screen = self?.activeScreen() ?? NSScreen.main ?? NSScreen()
                let menuBar = self?.menuBarHeight(on: screen) ?? 37
                let topInset = NotchMetrics.expandedTopInset(menuBarHeight: menuBar)
                let scrollMaxH = NotchMetrics.expandedScrollMaxHeight(screenFrameHeight: screen.frame.height)
                return AnyView(
                    NotchExpandedPanel(registry: registry, topInset: topInset, scrollMaxHeight: scrollMaxH)
                )
            },
            compactLeading: { [registry, weak self] in
                AnyView(NotchCompactSlotView(side: .leading, registry: registry, onWidth: { w in
                    Task { @MainActor in self?.leadingContentWidth = max(w, 1) }
                }))
            },
            compactTrailing: { [registry] in AnyView(NotchCompactSlotView(side: .trailing, registry: registry)) }
        )
        notch.transitionConfiguration = DynamicNotchTransitionConfiguration(
            openingAnimation: .bouncy(duration: 0.42),
            closingAnimation: .smooth(duration: 0.32),
            conversionAnimation: .snappy(duration: 0.55),
            skipIntermediateHides: true)
        self.notch = notch

        // 啟動時進入 compact；縮起側由 slot 設定收進實體劉海。
        await transition(to: .compact)
        startAutoPresentation()
        installMouseMonitors()
    }

    public func expand() async { await transition(to: .expanded) }
    public func compact() async { await transition(to: .compact) }
    public func hide() async { await transition(to: .hidden) }
    public func stop() {
        autoPresentationTask?.cancel()
        autoPresentationTask = nil
        removeMouseMonitors()
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

    /// 依滑鼠位置切換 compact panel 的點擊穿透：滑鼠在「左側內容 + 瀏海」命中區內 → 可互動；
    /// 否則穿透，讓瀏海右側的選單列狀態圖示可點。展開/隱藏時一律可互動。
    private func updateClickThrough() {
        guard let window = notch?.windowController?.window else { return }
        switch presentation {
        case .expanded, .hidden:
            mouseOverNotchArea = true
            if window.ignoresMouseEvents { window.ignoresMouseEvents = false }
        case .compact:
            let inside = compactHitRect().contains(NSEvent.mouseLocation)
            mouseOverNotchArea = inside
            if window.ignoresMouseEvents == inside { window.ignoresMouseEvents = !inside }
        }
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
        guard let notch, !isTransitioning else { return }

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
        guard let notch, presentation != nextPresentation, !isTransitioning else { return }

        isTransitioning = true
        switch nextPresentation {
        case .compact:
            await notch.compact()
            // Spike(收窄 panel)判定 FAIL：setFrame 破壞 DynamicNotchKit 內容置中，改走 Task 5 路徑 F。
        case .expanded:
            await notch.expand()
        case .hidden:
            await notch.hide()
        }
        presentation = nextPresentation
        presentationChangedAt = Date()
        isTransitioning = false

        switch nextPresentation {
        case .expanded: onActivityLevelChange?(.foreground)
        case .compact:  onActivityLevelChange?(.background)
        case .hidden:   onActivityLevelChange?(.idle)
        }
    }

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
        guard let notch, !isTransitioning else { return }
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

/// 展開面板（分頁版）。還原 docs/demo/index.html 的儀表板：頂部書籤分頁
/// （系統監控／模型配額／Agent 活動），一次只顯示一張 widget 的展開視圖。
/// 三 widget 直疊會把面板撐到溢出螢幕（頂端被劉海吃掉、底端被 Dock 裁掉且捲不到），
/// 分頁讓每張內容都短到完整可見，不再需要長捲動。
struct NotchExpandedPanel: View {
    let registry: WidgetRegistry
    /// DynamicNotchKit 已保留實體劉海高度，這裡只補一個視覺餘量（見 NotchMetrics.expandedTopInset）。
    let topInset: CGFloat
    /// 可捲區高度上限，依「半螢幕視窗」天花板計算（見 NotchMetrics.expandedScrollMaxHeight）。
    let scrollMaxHeight: CGFloat

    /// 面板固定寬，貼齊 demo 的 440pt 卡片。
    private let panelWidth: CGFloat = 440

    @State private var selectedID: String?
    /// 當前頁內容的自然高度（量測得到），用來決定可捲區「貼合 or 封頂自捲」。
    @State private var contentHeight: CGFloat = 0
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    private var l10n: L10n { L10n(rawValue: languageRaw) }

    private var widgets: [any NotchWidget] {
        registry.visibleSortedByPriority
    }

    private var leadingWidgets: [any NotchWidget] {
        _ = registry.layout.revision
        return registry.widgets(on: .leading)
    }

    private var trailingWidgets: [any NotchWidget] {
        _ = registry.layout.revision
        return registry.widgets(on: .trailing)
    }

    private var activeWidget: (any NotchWidget)? {
        if let selectedID, let match = widgets.first(where: { $0.id == selectedID }) {
            return match
        }
        return widgets.first
    }

    var body: some View {
        // DynamicNotchKit 把展開視窗寫死成半螢幕高（見 NotchMetrics.expandedScrollMaxHeight），是硬天花板。
        // 短頁（系統監控）量測後貼合內容；長頁（模型配額）封頂在半螢幕視窗內自捲，頂端錨點列與分頁列
        // 永遠穩定可見，不再被推出畫面。
        let resolvedHeight = contentHeight <= 0
            ? scrollMaxHeight
            : min(contentHeight, scrollMaxHeight)

        VStack(spacing: 10) {
            notchHeader
            if widgets.count > 1 {
                tabBar
            }

            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    if let activeWidget {
                        activeWidget.expandedView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .frame(height: resolvedHeight)
        }
        .padding(.top, topInset)
        .padding(.horizontal, 16)
        .padding(.bottom, NotchMetrics.expandedBottomMargin)
        .frame(width: panelWidth)
        .onChange(of: activeWidget?.id) { contentHeight = 0 }
    }

    /// 頂部錨點：重現實體瀏海兩側的 compact 資訊（左＝系統指標，右＝AI 摘要），中央留白讓出劉海位置。
    /// 給面板一個固定置頂的實體物件，內容不再貼著螢幕頂往上鑽。
    private var notchHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(leadingWidgets, id: \.id) { widget in
                    widget.compactView()
                }
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                ForEach(trailingWidgets, id: \.id) { widget in
                    widget.compactView()
                }
            }
        }
        .font(Theme.Fonts.compact())
        .foregroundStyle(Theme.Colors.text)
        .frame(maxWidth: .infinity)
        .frame(height: max(20, registry.layout.contentHeight + 4))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(widgets, id: \.id) { widget in
                tabButton(widget)
            }
        }
        .padding(3)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func tabButton(_ widget: any NotchWidget) -> some View {
        let isActive = activeWidget?.id == widget.id
        return Button {
            selectedID = widget.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: widget.settingsIconSystemName)
                    .font(.system(size: 11, weight: .semibold))
                Text(tabTitle(for: widget))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.1) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? Color.white.opacity(0.05) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tabTitle(for: widget))
    }

    /// 分頁標題（依語言偏好）。未知 widget 退回 settingsTitle。
    private func tabTitle(for widget: any NotchWidget) -> String {
        switch widget.id {
        case "system": return l10n.tabSystem
        case "token": return l10n.tabToken
        case "agent-activity": return l10n.tabAgent
        default: return widget.settingsTitle
        }
    }
}

private enum NotchPresentation {
    case compact
    case expanded
    case hidden
}

private enum NotchCompactSide {
    case leading
    case trailing
}

private struct NotchCompactSlotView: View {
    let side: NotchCompactSide
    let registry: WidgetRegistry
    var onWidth: ((CGFloat) -> Void) = { _ in }

    var body: some View {
        let _ = registry.layout.revision
        let _ = registry.visibilityRevision
        let notchSide: NotchSide = side == .leading ? .leading : .trailing
        let maxW = registry.layout.maxWidth(for: notchSide)
        let height = registry.layout.contentHeight
        Group {
            if registry.layout.isPinned(notchSide) {
                HStack(spacing: side == .leading ? 4 : 6) {
                    ForEach(registry.widgets(on: notchSide), id: \.id) { widget in
                        widget.compactView()
                    }
                }
                .frame(maxWidth: maxW, maxHeight: height, alignment: side == .leading ? .leading : .trailing)
                .frame(height: height)
                .clipped()
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: maxW, alignment: side == .leading ? .leading : .trailing)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { onWidth(min($0, maxW)) }
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .clipped()
            }
        }
        .onAppear { syncCollapsedWidth(notchSide) }
        .onChange(of: registry.layout.revision) { syncCollapsedWidth(notchSide) }
    }

    private func syncCollapsedWidth(_ notchSide: NotchSide) {
        if !registry.layout.isPinned(notchSide) { onWidth(0) }
    }
}
