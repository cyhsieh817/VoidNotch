//
//  ProviderSettingsView.swift — Token provider settings
//

import AppKit
import Observation
import SwiftUI
import VoidNotchKit

struct ProviderSettingsView: View {
    @Bindable var store: TokenStore
    @Bindable var registry: WidgetRegistry
    @Bindable var hookWiringStore: HookWiringStore
    let onRewireHook: (AgentActivityProviderKind) -> Void
    let onUnwireHook: (AgentActivityProviderKind) -> Void
    let onResetGaugePosition: () -> Void
    let onPreviewSound: (AlertSoundCategory) -> Void
    let onPreviewSpeech: (AgentSpeechLanguage) -> Void
    let launchdScheduleStore: LaunchdScheduleStore
    let updateCheckStore: UpdateCheckStore
    let onContentHeightChange: (CGFloat) -> Void

    init(
        store: TokenStore,
        registry: WidgetRegistry,
        hookWiringStore: HookWiringStore,
        onRewireHook: @escaping (AgentActivityProviderKind) -> Void,
        onUnwireHook: @escaping (AgentActivityProviderKind) -> Void,
        onResetGaugePosition: @escaping () -> Void = {},
        onPreviewSound: @escaping (AlertSoundCategory) -> Void = { _ in },
        onPreviewSpeech: @escaping (AgentSpeechLanguage) -> Void = { _ in },
        launchdScheduleStore: LaunchdScheduleStore,
        updateCheckStore: UpdateCheckStore,
        onContentHeightChange: @escaping (CGFloat) -> Void = { _ in })
    {
        self.store = store
        self.registry = registry
        self.hookWiringStore = hookWiringStore
        self.onRewireHook = onRewireHook
        self.onUnwireHook = onUnwireHook
        self.onResetGaugePosition = onResetGaugePosition
        self.onPreviewSound = onPreviewSound
        self.onPreviewSpeech = onPreviewSpeech
        self.launchdScheduleStore = launchdScheduleStore
        self.updateCheckStore = updateCheckStore
        self.onContentHeightChange = onContentHeightChange
    }

    @State private var selectedProvider: TokenProviderKind = .claude
    @State private var selectedTab: SettingsTab = .layout
    @State private var selectedLayoutTab: LayoutTab = .notch
    @State private var selectedProviderTab: ProviderTab = .usage
    @State private var selectedAlertsTab: AlertsTab = .sound
    @AppStorage(NotchCompactPreferenceKey.leadingPinned) private var keepLeftOpen = true
    @AppStorage(NotchCompactPreferenceKey.trailingPinned) private var keepRightOpen = false
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue
    @AppStorage(AppDelegate.peonAudioPreferenceKey) private var peonAudioEnabled = true

    private var l10n: L10n { L10n(rawValue: languageRaw) }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var relativeLastChecked: String? {
        guard let lastCheckedAt = updateCheckStore.lastCheckedAt else { return nil }
        Self.relativeDateFormatter.locale = l10n.language == .zhTW
            ? Locale(identifier: "zh_TW")
            : Locale(identifier: "en_US")
        return Self.relativeDateFormatter.localizedString(for: lastCheckedAt, relativeTo: Date())
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case layout
        case system
        case scheduled
        case providers
        case alerts

        var id: String { rawValue }

        func title(l10n: L10n) -> String {
            switch self {
            case .layout: return l10n.settingsTabLayout
            case .system: return l10n.settingsTabSystem
            case .scheduled: return l10n.settingsTabScheduled
            case .providers: return l10n.settingsTabProviders
            case .alerts: return l10n.settingsTabAlerts
            }
        }
    }

    /// 版面分頁的子頁籤。零捲動紀律：每個子頁一屏塞得下，超過就再切一個子頁，不放捲動容器。
    private enum LayoutTab: String, CaseIterable, Identifiable {
        case notch
        case menubar
        case gauge

        var id: String { rawValue }

        func title(l10n: L10n) -> String {
            switch self {
            case .notch: return l10n.layoutTabNotch
            case .menubar: return l10n.layoutTabMenubar
            case .gauge: return l10n.layoutTabGauge
            }
        }
    }

    /// Provider 細節的子頁籤：用量／資訊／帳號。
    private enum ProviderTab: String, CaseIterable, Identifiable {
        case usage
        case details
        case accounts

        var id: String { rawValue }

        func title(l10n: L10n) -> String {
            switch self {
            case .usage: return l10n.providerTabUsage
            case .details: return l10n.providerTabDetails
            case .accounts: return l10n.providerTabAccounts
            }
        }
    }

    private enum AlertsTab: String, CaseIterable, Identifiable {
        case sound
        case speech
        case agentWiring

        var id: String { rawValue }

        func title(l10n: L10n) -> String {
            switch self {
            case .sound: return l10n.alertsTabSound
            case .speech: return l10n.alertsTabSpeech
            case .agentWiring: return l10n.alertsTabAgentWiring
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            settingsTabBar
            Divider()
            settingsTabContent
            Divider()
            quitFooter
        }
        .frame(width: SettingsMetrics.windowWidth)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SettingsContentHeightPreferenceKey.self,
                    value: geometry.size.height)
            }
        }
        .onPreferenceChange(SettingsContentHeightPreferenceKey.self) { height in
            onContentHeightChange(height)
        }
        .onAppear {
            if !store.allProviderKinds.contains(selectedProvider) {
                selectedProvider = store.allProviderKinds.first ?? .claude
            }
        }
        .task {
            await store.refreshAccountCatalog()
        }
        .onAppear {
            hookWiringStore.refresh()
        }
    }

    private var settingsTabBar: some View {
        Picker("Settings Tab", selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Text(tab.title(l10n: l10n)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 10)
    }

    /// 零捲動紀律：所有分頁一律一屏塞得下，全域無捲動容器。
    /// 內容長到塞不下時，正解是再切一個子頁籤，不是把捲軸加回來。
    @ViewBuilder
    private var settingsTabContent: some View {
        Group {
            switch selectedTab {
            case .layout: layoutTabContent
            case .system:
                page {
                    updateSection
                    Divider()
                    SystemMetricsSettingsRow(l10n: l10n)
                }
            case .scheduled:
                // 排程分頁是 Settings 的一級頁面，也是資料總覽入口；Layout 的 widget 可見性開關只治理瀏海面板呈現，不隱藏此分頁，避免使用者失去唯一的排程檢視入口。
                page {
                    LaunchdScheduleExpandedView(
                        store: launchdScheduleStore,
                        listMaxHeight: 480,
                        allowsRemoval: true)
                }
            case .providers:
                VStack(spacing: 0) {
                    providerPageHeader
                    HStack(alignment: .top, spacing: 0) {
                        providerSidebar
                        Divider()
                        providerDetail
                    }
                }
            case .alerts:
                VStack(spacing: 0) {
                    subTabBar(
                        selection: $selectedAlertsTab,
                        titles: { $0.title(l10n: l10n) })
                    .padding(.horizontal, SettingsMetrics.inset)

                    switch selectedAlertsTab {
                    case .sound:
                        page {
                            AlertSoundSettingsView(
                                l10n: l10n,
                                isEnabled: $peonAudioEnabled,
                                onPreviewSound: onPreviewSound)
                        }
                    case .speech:
                        page {
                            AgentSpeechSettingsView(
                                l10n: l10n,
                                onPreviewSpeech: onPreviewSpeech)
                        }
                    case .agentWiring:
                        page {
                            HookWiringSettingsView(
                                l10n: l10n,
                                states: hookWiringStore.states,
                                onRewire: onRewireHook,
                                onUnwire: onUnwireHook)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 一頁的骨架：內容由上往下堆，永不捲動。
    @ViewBuilder
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
    }

    /// 常駐「軟體更新」小節：有新版橫幅／已是最新／檢查中，永遠附「立即檢查」。
    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.updateSectionTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            if updateCheckStore.isChecking {
                ProgressView()
                    .controlSize(.mini)
            } else if let availableUpdate = updateCheckStore.availableUpdate {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(l10n.updateAvailable(availableUpdate.version))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let url = URL(string: availableUpdate.url) {
                        Link(l10n.updateDownload, destination: url)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            } else {
                Text(l10n.updateUpToDate(updateCheckStore.currentVersion))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let relative = relativeLastChecked {
                Text(l10n.updateLastChecked(relative))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Button(l10n.updateCheckNow) {
                Task {
                    await updateCheckStore.checkIfDue(force: true)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .disabled(updateCheckStore.isChecking)
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var layoutTabContent: some View {
        VStack(spacing: 0) {
            subTabBar(
                selection: $selectedLayoutTab,
                titles: { $0.title(l10n: l10n) })
            .padding(.horizontal, SettingsMetrics.inset)

            switch selectedLayoutTab {
            case .notch:
                page {
                    NotchLayoutSettingsPanel(
                        l10n: l10n,
                        registry: registry,
                        keepLeftOpen: $keepLeftOpen,
                        keepRightOpen: $keepRightOpen,
                        compactProviderChoices: store.selectedProviderKinds,
                        compactDisplayProvider: Binding(
                            get: { store.compactDisplayProvider },
                            set: { store.setCompactDisplayProvider($0) }))
                    Divider()
                    WidgetVisibilitySettingsRow(l10n: l10n, registry: registry)
                }
            case .menubar:
                page {
                    MenubarModeSettingsRow(language: AppLanguage.resolve(languageRaw))
                    Divider()
                    MenubarItemsSettingsRow(l10n: l10n)
                }
            case .gauge:
                page { GaugeSettingsRow(l10n: l10n, onResetPosition: onResetGaugePosition) }
            }
        }
    }

    /// 子頁籤列：比主頁籤低一階（較小、無底線分隔），避免與主頁籤搶視覺層級。
    private func subTabBar<Tab: Hashable & Identifiable & CaseIterable>(
        selection: Binding<Tab>,
        titles: @escaping (Tab) -> String
    ) -> some View where Tab.AllCases == [Tab] {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                let isSelected = selection.wrappedValue == tab
                Button {
                    selection.wrappedValue = tab
                } label: {
                    Text(titles(tab))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Color.white.opacity(isSelected ? 0.16 : 0.04),
                            in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // plain Button 包 styled Text 在 AX 樹裡沒有標題（實測 title=null），
                // 對輔助技術等同無名按鈕；明確補上標籤與選取狀態。
                .accessibilityLabel(titles(tab))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(selectedTab.title(l10n: l10n))
                .font(.headline)

            Spacer()

            toolbarPickerLabel(l10n.languageLabel)

            Picker("Language", selection: $languageRaw) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.pickerLabel).tag(language.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 118)
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 14)
    }

    /// 設定視窗常駐退出：與 status menu 的 `quitVoidNotch()` 同一路徑（NSApp.terminate）。
    private var quitFooter: some View {
        HStack {
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label(l10n.menuQuit, systemImage: "power")
            }
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 12)
    }

    private func toolbarPickerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var providerSidebar: some View {
        VStack(spacing: 9) {
            ForEach(store.allProviderKinds) { provider in
                ProviderSidebarRow(
                    provider: provider,
                    usage: usage(for: provider),
                    isSelected: selectedProvider == provider,
                    isEnabled: store.isProviderEnabled(provider),
                    canDisable: store.canDisableProvider(provider),
                    onSelect: { selectedProvider = provider },
                    onToggle: { store.setProvider(provider, enabled: $0) })
            }
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 12)
        .frame(width: SettingsMetrics.sidebarWidth, alignment: .top)
    }

    private var providerPageHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.providersTitle)
                    .font(.headline)
                Text("\(store.providerHealthSummary) · \(l10n.needCheck(store.attentionProviderCount))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            toolbarPickerLabel(l10n.metricLabel)

            Picker(
                "Metric",
                selection: Binding(
                    get: { store.usageDisplayMode },
                    set: { store.setUsageDisplayMode($0) }))
            {
                ForEach(TokenUsageDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)

            Button {
                Task { await store.refresh() }
            } label: {
                Label(store.isRefreshing ? l10n.refreshing : l10n.refresh, systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 10)
    }

    /// 常駐：身分列 + 狀態橫幅（切子頁籤時不該閃走）。細節分三個子頁，各自一屏塞得下。
    private var providerDetail: some View {
        let usage = usage(for: selectedProvider)
        return VStack(alignment: .leading, spacing: 16) {
            ProviderDetailHeader(
                provider: selectedProvider,
                usage: usage,
                isEnabled: store.isProviderEnabled(selectedProvider),
                canDisable: store.canDisableProvider(selectedProvider),
                onRefresh: { Task { await store.refresh() } },
                onToggle: { store.setProvider(selectedProvider, enabled: $0) })

            ProviderStateBanner(usage: usage)

            subTabBar(
                selection: $selectedProviderTab,
                titles: { $0.title(l10n: l10n) })

            switch selectedProviderTab {
            case .usage:
                ProviderUsageDetail(usage: usage, displayMode: store.usageDisplayMode)
            case .details:
                VStack(alignment: .leading, spacing: 20) {
                    ProviderIconPickerRow(provider: selectedProvider)
                        .id(selectedProvider.rawValue)
                    ProviderCapabilityMatrix(provider: selectedProvider, usage: usage)
                    ProviderInfoGrid(usage: usage)
                }
            case .accounts:
                providerAccounts
            }
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 帳號管理目前僅 Antigravity 需要；其餘 provider 直接說明「不需帳號」，而不是給一片空白。
    @ViewBuilder
    private var providerAccounts: some View {
        if selectedProvider == .antigravity {
            ProviderAccountSection(
                provider: selectedProvider,
                accounts: store.accounts(for: selectedProvider),
                accountUsages: store.accountUsages(for: selectedProvider),
                errorMessage: store.accountErrorMessage(for: selectedProvider),
                onRefresh: {
                    Task {
                        await store.refreshAccounts(for: selectedProvider)
                        await store.refreshAccountUsages(for: selectedProvider)
                    }
                },
                onImport: { Task { await store.importAccount(for: selectedProvider) } },
                onImportRaw: { accountImport in
                    Task { await store.importAccounts(accountImport, for: selectedProvider) }
                },
                onSelect: { account in Task { await store.setActiveAccount(account.id, for: selectedProvider) } },
                onApplyToCLI: { account in Task { await store.applyAccountToAgyCLI(account.id, for: selectedProvider) } },
                onExport: { accountIDs in
                    await store.exportAccounts(accountIDs, for: selectedProvider)
                },
                onSetDisabled: { account, disabled in
                    Task {
                        await store.setAccountDisabled(
                            account.id,
                            disabled: disabled,
                            reason: disabled ? "Skipped manually" : nil,
                            for: selectedProvider)
                    }
                },
                onDelete: { account in Task { await store.deleteAccount(account.id, for: selectedProvider) } })
        } else {
            NotchEmptyState(
                icon: "person.crop.circle.badge.checkmark",
                title: l10n.providerAccountsUnsupported,
                subtitle: l10n.providerAccountsUnsupportedHint,
                tint: selectedProvider.tint)
        }
    }

    private func usage(for provider: TokenProviderKind) -> ProviderUsage {
        store.providers.first(where: { $0.provider == provider }) ?? ProviderUsage.placeholder(for: provider)
    }
}

private struct SettingsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ProviderIconPickerRow: View {
    let provider: TokenProviderKind
    @AppStorage private var choiceRawValue: String

    init(provider: TokenProviderKind) {
        self.provider = provider
        _choiceRawValue = AppStorage(
            wrappedValue: ProviderIconChoice.default.rawValue,
            ProviderIconChoice.preferenceKey(for: provider))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Icon")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            // segmented Picker 無法可靠渲染各段不同 SwiftUI artwork，改為明確 button group。
            HStack(spacing: 4) {
                ForEach(ProviderIconChoice.allCases) { choice in
                    let isSelected = selectedChoice == choice
                    Button {
                        choiceRawValue = choice.rawValue
                    } label: {
                        ProviderGlyphArtwork(
                            provider: provider,
                            choice: choice,
                            size: 22,
                            weight: .semibold)
                            .foregroundStyle(provider.tint)
                            .frame(width: 44, height: 36)
                            .background(
                                provider.tint.opacity(isSelected ? 0.18 : 0.04),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        isSelected
                                            ? provider.tint.opacity(0.55)
                                            : Color.white.opacity(0.08),
                                        lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .help(choice.title)
                }
            }
            .frame(width: 284)

            Text(selectedChoice.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var selectedChoice: ProviderIconChoice {
        ProviderIconChoice(rawValue: choiceRawValue) ?? .default
    }
}

// provider 圖示/狀態徽章/配額列 → App/Components/*（共用元件）
// provider 圖示/色票與狀態色 → App/Theme/ProviderAppearance.swift（單一真相）
