//
//  VoidNotchApp.swift — @main 進入點
//
//  ⚠️ Xcode app target 專屬。
//  組裝：資料層(已驗證) → @Observable 包裝 → widget 註冊 → NotchShell(DynamicNotchKit) → 狀態列控制展開/收合。
//

import SwiftUI
import AppKit
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
    private let systemMonitor = ObservableSystemMonitor()
    private let tokenStore = TokenStore(
        usageProvider: CodexBarTokenUsageProvider(),
        accountManager: CodexBarTokenAccountManager())
    private let agentActivityStore = AgentActivityStore(activityProvider: PeonPingAgentActivityProvider())
    private let registry = WidgetRegistry()
    private var shell: NotchShell?
    private var statusItem: NSStatusItem?
    private var providerSettingsWindow: NSWindow?
    private var currentLanguage = AppLanguage.resolve(
        UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
    private var languageObserver: NSObjectProtocol?

    private var l10n: L10n { L10n(currentLanguage) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerDefaultPreferences()
        observeLanguageChanges()

        // 1. 啟動已驗證的系統監控輪詢（2 秒）
        systemMonitor.start(interval: 2.0)
        Task { await tokenStore.refreshAccountCatalog() }
        tokenStore.startPolling(interval: 300)
        agentActivityStore.startPolling(interval: 15)

        // 2. 註冊 widget（system 偏左、AI 摘要偏右；agent compact 狀態併入 AI 摘要點）
        registry.register(SystemWidget(monitor: systemMonitor))
        registry.register(TokenWidget(store: tokenStore, agentStore: agentActivityStore))
        registry.register(AgentActivityWidget(store: agentActivityStore))

        // 3. 建外殼 → compact 左右側由使用者設定控制
        let shell = NotchShell(
            registry: registry,
            openSettings: { [weak self] in self?.openTokenProviderSettings() },
            onActivityLevelChange: { [weak self] level in self?.systemMonitor.setActivityLevel(level) })
        self.shell = shell
        Task { await shell.start() }

        installStatusItem()
    }

    private func registerDefaultPreferences() {
        UserDefaults.standard.register(defaults: [
            NotchCompactPreferenceKey.leadingPinned: true,
            NotchCompactPreferenceKey.trailingPinned: false,
            NotchCompactPreferenceKey.leadingMaxWidth: Double(NotchCompactLayout.defaultLeadingWidth),
            NotchCompactPreferenceKey.trailingMaxWidth: Double(NotchCompactLayout.defaultTrailingWidth),
            NotchCompactPreferenceKey.contentHeight: Double(NotchCompactLayout.defaultHeight),
        ])
        SystemMetricPreferences.registerDefaults()
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemMonitor.stop()
        tokenStore.stopPolling()
        agentActivityStore.stopPolling()
        shell?.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "VoidNotch")
        item.button?.imagePosition = .imageOnly
        item.menu = buildStatusMenu()

        statusItem = item
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: l10n.menuSettings, action: #selector(openTokenProviderSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: l10n.menuShowDashboard, action: #selector(showDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: l10n.menuCollapse, action: #selector(tuckIntoNotch), keyEquivalent: "t"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: l10n.menuRefreshTokens, action: #selector(refreshTokenUsage), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: l10n.menuRefreshAgents, action: #selector(refreshAgentActivity), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: l10n.menuQuit, action: #selector(quitVoidNotch), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    /// 語言偏好變更（設定視窗的切換器寫入 UserDefaults）→ 重建狀態列選單與視窗標題。
    /// SwiftUI view 各自透過 @AppStorage 反應，這裡只補 AppKit 側。
    private func observeLanguageChanges() {
        languageObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated { self?.syncLanguageIfNeeded() }
        }
    }

    private func syncLanguageIfNeeded() {
        let language = AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
        guard language != currentLanguage else { return }
        currentLanguage = language
        statusItem?.menu = buildStatusMenu()
        providerSettingsWindow?.title = l10n.settingsWindowTitle
    }

    @objc private func openTokenProviderSettings() {
        if let providerSettingsWindow {
            providerSettingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = l10n.settingsWindowTitle
        window.contentViewController = NSHostingController(rootView: ProviderSettingsView(store: tokenStore, registry: registry))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        providerSettingsWindow = window
    }

    @objc private func showDashboard() {
        Task { await shell?.expand() }
    }

    @objc private func tuckIntoNotch() {
        Task { await shell?.compact() }
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
