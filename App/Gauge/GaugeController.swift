import AppKit
import SwiftUI
import VoidNotchKit

@MainActor
final class GaugeController: NSObject, NSMenuDelegate {
    private let systemMonitor: ObservableSystemMonitor
    private let tokenStore: TokenStore
    private let agentStore: AgentActivityStore
    private var panel: GaugePanel?
    private var frameObserver: NSObjectProtocol?
    private var lastAppliedEnabledState: Bool?

    private let frameKey = "VoidNotch.gauge.frame"
    private let enabledKey = "VoidNotch.gauge.enabled"
    private let clickThroughKey = "VoidNotch.gauge.clickThrough"
    private let skinKey = "VoidNotch.gauge.skin"
    private let lockedKey = "VoidNotch.gauge.locked"
    private let scaleKey = "VoidNotch.gauge.scale"

    init(systemMonitor: ObservableSystemMonitor, tokenStore: TokenStore, agentStore: AgentActivityStore) {
        self.systemMonitor = systemMonitor
        self.tokenStore = tokenStore
        self.agentStore = agentStore
        super.init()
    }

    func applyEnabledState() {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        // enabled 未變時仍可能因選集變更而需調整寬度；不得重跑 show/hide。
        guard enabled != lastAppliedEnabledState else {
            if enabled { applyContentSizedFrameIfNeeded() }
            return
        }
        lastAppliedEnabledState = enabled
        enabled ? show() : hide()
    }

    func show() {
        if let panel, panel.isVisible { return }

        if panel == nil {
            let rect = savedFrame() ?? defaultFrame()
            let panel = GaugePanel(contentRect: rect)
            let host = NSHostingView(rootView: GaugeContentView(
                systemMonitor: systemMonitor, tokenStore: tokenStore, agentStore: agentStore))
            host.sizingOptions = []
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(origin: .zero, size: rect.size)
            host.autoresizingMask = [.width, .height]
            host.menu = buildContextMenu()          // 右鍵選單
            panel.contentView = host
            panel.ignoresMouseEvents = UserDefaults.standard.bool(forKey: clickThroughKey)
            panel.isMovableByWindowBackground = !UserDefaults.standard.bool(forKey: lockedKey)
            self.panel = panel
            observeFramePersistence()
        }
        panel?.setFrame(savedFrame() ?? defaultFrame(), display: true)
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil); persistFrame() }

    func resetPosition() {
        let f = defaultFrame()
        panel?.setFrame(f, display: true, animate: true)
        UserDefaults.standard.set(NSStringFromRect(f), forKey: frameKey)
    }

    // MARK: - Frame 持久化
    private func savedFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: frameKey) else { return nil }
        let r = NSRectFromString(s)
        guard r.width > 0 else { return nil }
        // panel 尚未建立時 screen 走 NSScreen.main（clamped 內 fallback）
        return clamped(NSRect(origin: r.origin, size: contentSize()), to: panel?.screen)
    }
    private func defaultFrame() -> NSRect {
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = contentSize()
        let w = size.width, h = size.height
        return NSRect(x: vf.maxX - w - 24, y: vf.maxY - h - 24, width: w, height: h)
    }
    private func contentSize() -> NSSize {
        let base = GaugeMetrics.baseSize(itemCount: DisplaySelectionStore.items(for: .gauge).count)
        let scale = GaugeMetrics.scale(from: .standard)
        return NSSize(width: base.width * scale, height: base.height * scale)
    }

    /// 將 rect 收回 screen.visibleFrame 內（尺寸大於可視範圍時貼齊左/下緣）。
    private func clamped(_ rect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? NSScreen.main else { return rect }
        let vf = screen.visibleFrame
        let w = rect.width, h = rect.height
        // 先夾入 [min, max-size]，再確保不小於 min（寬/高超過可視範圍時貼左/下緣）
        var x = min(max(rect.origin.x, vf.minX), vf.maxX - w)
        var y = min(max(rect.origin.y, vf.minY), vf.maxY - h)
        x = max(x, vf.minX)
        y = max(y, vf.minY)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    /// 僅在推導尺寸與目前 panel 不同時才 setFrame，避免無條件 layout pass。
    private func applyContentSizedFrameIfNeeded() {
        guard let panel else { return }
        let size = contentSize()
        guard panel.frame.size != size else { return }
        let next = clamped(NSRect(origin: panel.frame.origin, size: size), to: panel.screen)
        panel.setFrame(next, display: true, animate: true)
    }
    private func persistFrame() {
        guard let f = panel?.frame else { return }
        let value = NSStringFromRect(f)
        guard UserDefaults.standard.string(forKey: frameKey) != value else { return }
        UserDefaults.standard.set(value, forKey: frameKey)
    }
    private func observeFramePersistence() {
        guard let panel else { return }
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistFrame() }
        }
    }

    // MARK: - 右鍵選單
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    // menuNeedsUpdate 動態重建（項目勾選狀態隨選集變）
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // 顯示項目 submenu
        let itemsMenu = NSMenu()
        let current = DisplaySelectionStore.items(for: .gauge)
        let lang = AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
        for item in DisplayItem.catalog {
            let mi = NSMenuItem(title: item.label(language: lang), action: #selector(toggleItem(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = item.storageKey
            mi.state = current.contains(item) ? .on : .off
            // 守門：達 4 且未選 → disable；剩 1 且已選 → disable
            if current.contains(item) {
                mi.isEnabled = DisplaySelectionStore.canRemove(item, for: .gauge)
            } else {
                mi.isEnabled = DisplaySelectionStore.canAdd(for: .gauge)
            }
            itemsMenu.addItem(mi)
        }
        let l10n = L10n(lang)
        let itemsRoot = NSMenuItem(title: l10n.gaugeMenuItems, action: nil, keyEquivalent: "")
        itemsRoot.submenu = itemsMenu
        menu.addItem(itemsRoot)

        // 外觀 submenu
        let skinMenu = NSMenu()
        let curSkin = UserDefaults.standard.string(forKey: skinKey) ?? GaugeSkinRegistry.shared.defaultSkinID
        for skin in GaugeSkinRegistry.shared.all {
            let mi = NSMenuItem(title: skin.displayName(language: lang), action: #selector(chooseSkin(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = skin.id
            mi.state = skin.id == curSkin ? .on : .off
            skinMenu.addItem(mi)
        }
        let skinRoot = NSMenuItem(title: l10n.gaugeSkinLabel, action: nil, keyEquivalent: "")
        skinRoot.submenu = skinMenu
        menu.addItem(skinRoot)

        // 大小 submenu
        let sizeMenu = NSMenu()
        let currentScale = GaugeMetrics.scale(from: .standard)
        let scaleOptions: [(Double, String)] = [
            (0.8, l10n.gaugeSizeSmall),
            (1.0, l10n.gaugeSizeStandard),
            (1.25, l10n.gaugeSizeLarge),
            (1.5, l10n.gaugeSizeXLarge),
        ]
        for (scale, title) in scaleOptions {
            let mi = NSMenuItem(title: title, action: #selector(chooseScale(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = NSNumber(value: scale)
            mi.state = abs(currentScale - CGFloat(scale)) < 0.01 ? .on : .off
            sizeMenu.addItem(mi)
        }
        let sizeRoot = NSMenuItem(title: l10n.gaugeSizeLabel, action: nil, keyEquivalent: "")
        sizeRoot.submenu = sizeMenu
        menu.addItem(sizeRoot)

        menu.addItem(.separator())
        addCheckable(menu, l10n.gaugeClickThrough, #selector(toggleClickThrough), clickThroughKey)
        addCheckable(menu, l10n.gaugeLockPosition, #selector(toggleLocked), lockedKey)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: l10n.gaugeHide, action: #selector(hideGauge), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
    }

    private func addCheckable(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        menu.addItem(mi)
    }

    // MARK: - 動作
    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let item = DisplayItem(storageKey: key) else { return }
        var current = DisplaySelectionStore.items(for: .gauge)
        if current.contains(item) {
            guard DisplaySelectionStore.canRemove(item, for: .gauge) else { return }
            current.removeAll { $0 == item }
        } else {
            guard DisplaySelectionStore.canAdd(for: .gauge) else { return }
            current.append(item)
        }
        DisplaySelectionStore.setItems(current, for: .gauge)
        applyContentSizedFrameIfNeeded()
    }
    @objc private func chooseSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: skinKey)
    }
    @objc private func chooseScale(_ sender: NSMenuItem) {
        guard let value = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        UserDefaults.standard.set(value, forKey: scaleKey)
        applyContentSizedFrameIfNeeded()
    }
    @objc private func toggleClickThrough() {
        let v = !UserDefaults.standard.bool(forKey: clickThroughKey)
        UserDefaults.standard.set(v, forKey: clickThroughKey)
        panel?.ignoresMouseEvents = v
    }
    @objc private func toggleLocked() {
        let v = !UserDefaults.standard.bool(forKey: lockedKey)
        UserDefaults.standard.set(v, forKey: lockedKey)
        panel?.isMovableByWindowBackground = !v
    }
    @objc private func hideGauge() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        hide()
    }
}
