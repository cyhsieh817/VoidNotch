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
    @State private var selectedProvider: TokenProviderKind = .claude
    @AppStorage(NotchCompactPreferenceKey.leadingPinned) private var keepLeftOpen = true
    @AppStorage(NotchCompactPreferenceKey.trailingPinned) private var keepRightOpen = false
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    private var l10n: L10n { L10n(rawValue: languageRaw) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
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
            Divider()
            SystemMetricsSettingsRow(l10n: l10n)
            Divider()
            HStack(spacing: 0) {
                providerSidebar
                Divider()
                providerDetail
            }
        }
        .frame(width: 860, height: 720)
        .onAppear {
            if !store.allProviderKinds.contains(selectedProvider) {
                selectedProvider = store.allProviderKinds.first ?? .claude
            }
        }
        .task {
            await store.refreshAccountCatalog()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.providersTitle)
                    .font(.headline)
                Text("\(store.providerHealthSummary) · \(l10n.needCheck(store.attentionProviderCount))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            toolbarPickerLabel(l10n.languageLabel)

            Picker("Language", selection: $languageRaw) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.pickerLabel).tag(language.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)

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
        .padding(.horizontal, 18)
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
        ScrollView {
            VStack(spacing: 7) {
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
            .padding(10)
        }
        .frame(width: 295)
    }

    private var providerDetail: some View {
        let usage = usage(for: selectedProvider)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProviderDetailHeader(
                    provider: selectedProvider,
                    usage: usage,
                    isEnabled: store.isProviderEnabled(selectedProvider),
                    canDisable: store.canDisableProvider(selectedProvider),
                    onRefresh: { Task { await store.refresh() } },
                    onToggle: { store.setProvider(selectedProvider, enabled: $0) })

                ProviderStateBanner(usage: usage)

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

                ProviderCapabilityMatrix(provider: selectedProvider, usage: usage)

                ProviderInfoGrid(usage: usage)

                ProviderUsageDetail(
                    usage: usage,
                    displayMode: store.usageDisplayMode)
            }
            .padding(22)
        }
    }

    private func usage(for provider: TokenProviderKind) -> ProviderUsage {
        store.providers.first(where: { $0.provider == provider }) ?? ProviderUsage.placeholder(for: provider)
    }
}

private struct ProviderAccountSection: View {
    let provider: TokenProviderKind
    let accounts: [ProviderAccount]
    let accountUsages: [ProviderAccountUsage]
    let errorMessage: String?
    let onRefresh: () -> Void
    let onImport: () -> Void
    let onImportRaw: (ProviderAccountImport) -> Void
    let onSelect: (ProviderAccount) -> Void
    let onExport: ([UUID]) async -> ProviderAccountExport?
    let onSetDisabled: (ProviderAccount, Bool) -> Void
    let onDelete: (ProviderAccount) -> Void

    @State private var pendingDeletion: ProviderAccount?
    @State private var isManualImportPresented = false
    @State private var isExportPresented = false
    @State private var accountExport: ProviderAccountExport?
    @State private var manualImportLabel = ""
    @State private var manualImportValue = ""

    var body: some View {
        if provider == .antigravity {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Accounts")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(accounts.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(provider.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(provider.tint.opacity(0.14), in: Capsule())

                    if !accountUsages.isEmpty {
                        Text("\(availableUsageCount)/\(accounts.count) live")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh saved AGY accounts")

                    Button(action: onImport) {
                        Label("Import Current", systemImage: "tray.and.arrow.down")
                    }
                    .help("Import the current Antigravity Google OAuth account")

                    Button {
                        Task {
                            accountExport = await onExport(accounts.map(\.id))
                            isExportPresented = accountExport != nil
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(accounts.isEmpty)
                    .help("Export saved AGY accounts as JSON")

                    Button {
                        isManualImportPresented = true
                    } label: {
                        Label("Add Token", systemImage: "plus")
                    }
                    .help("Paste an AGY refresh token or Antigravity account JSON")
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }

                if accounts.isEmpty {
                    NotchEmptyState(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "No saved AGY accounts.",
                        subtitle: "Import the current Antigravity OAuth account, then switch accounts here.",
                        tint: provider.tint)
                } else {
                    VStack(spacing: 8) {
                        ForEach(accounts) { account in
                            ProviderAccountRow(
                                account: account,
                                usage: usage(for: account),
                                tint: provider.tint,
                                onSelect: { onSelect(account) },
                                onSetDisabled: { disabled in onSetDisabled(account, disabled) },
                                onDelete: { pendingDeletion = account })
                        }
                    }
                }
            }
            .confirmationDialog(
                "Remove AGY account?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }),
                presenting: pendingDeletion)
            { account in
                Button("Remove \(account.label)", role: .destructive) {
                    onDelete(account)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { account in
                Text(account.displaySubtitle)
            }
            .sheet(isPresented: $isManualImportPresented) {
                ProviderAccountImportSheet(
                    provider: provider,
                    label: $manualImportLabel,
                    rawValue: $manualImportValue,
                    onCancel: {
                        isManualImportPresented = false
                    },
                    onImport: {
                        onImportRaw(
                            ProviderAccountImport(
                                label: manualImportLabel,
                                rawValue: manualImportValue))
                        manualImportLabel = ""
                        manualImportValue = ""
                        isManualImportPresented = false
                    })
            }
            .sheet(isPresented: $isExportPresented) {
                if let accountExport {
                    ProviderAccountExportSheet(
                        accountExport: accountExport,
                        onCopy: { copyToPasteboard(accountExport.payload) },
                        onClose: {
                            isExportPresented = false
                        })
                }
            }
        }
    }

    private var availableUsageCount: Int {
        accountUsages.filter { $0.usage.status == .available }.count
    }

    private func usage(for account: ProviderAccount) -> ProviderAccountUsage? {
        accountUsages.first(where: { $0.account.id == account.id })
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct ProviderAccountImportSheet: View {
    let provider: TokenProviderKind
    @Binding var label: String
    @Binding var rawValue: String
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderIcon(provider: provider, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add AGY Account")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Refresh token, OAuth JSON, or exported accounts JSON")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Label", text: $label)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $rawValue)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 170)
                .scrollContentBackground(.hidden)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Import", action: onImport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 430)
    }
}

private struct ProviderAccountExportSheet: View {
    let accountExport: ProviderAccountExport
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderIcon(provider: accountExport.provider, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export AGY Accounts")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(accountExport.accountCount) account(s) · \(accountExport.fileName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: .constant(accountExport.payload))
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 210)
                .scrollContentBackground(.hidden)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("Close", action: onClose)
                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 470)
    }
}

private struct ProviderAccountRow: View {
    let account: ProviderAccount
    let usage: ProviderAccountUsage?
    let tint: Color
    let onSelect: () -> Void
    let onSetDisabled: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: accountIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accountIconColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(account.label)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            if let usage {
                                ProviderStatusDot(status: usage.usage.status, size: 5)
                            }
                            if account.isActive {
                                Text("Active")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(tint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tint.opacity(0.13), in: Capsule())
                            }
                            if account.isDisabled {
                                Text("Skipped")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.13), in: Capsule())
                            }
                            if usage?.isRecommended == true {
                                Text("Best")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.13), in: Capsule())
                            }
                        }
                        HStack(spacing: 6) {
                            Text(usage?.quotaSummaryText ?? account.displaySubtitle)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(usage == nil ? Color.secondary : Color.primary.opacity(0.82))
                                .lineLimit(1)
                            if let usage {
                                Text(usage.detailSummaryText)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(account.isActive || account.isDisabled)

            Button {
                onSetDisabled(!account.isDisabled)
            } label: {
                Image(systemName: account.isDisabled ? "play.circle" : "pause.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(account.isDisabled ? tint : .secondary)
            .help(account.isDisabled ? "Enable account" : "Skip account")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove account")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(account.isActive ? tint.opacity(0.10) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(account.isActive ? tint.opacity(0.20) : Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var accountIconName: String {
        if account.isDisabled {
            return "person.crop.circle.badge.xmark"
        }
        return account.isActive ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle"
    }

    private var accountIconColor: Color {
        if account.isDisabled {
            return .orange
        }
        return account.isActive ? tint : .secondary
    }
}

private struct NotchLayoutSettingsPanel: View {
    let l10n: L10n
    @Bindable var registry: WidgetRegistry
    @Binding var keepLeftOpen: Bool
    @Binding var keepRightOpen: Bool
    let compactProviderChoices: [TokenProviderKind]
    @Binding var compactDisplayProvider: TokenProviderKind?

    private var layout: NotchCompactLayoutStore { registry.layout }

    var body: some View {
        let _ = layout.revision
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(l10n.compactRowTitle, systemImage: "rectangle.compress.vertical")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text(l10n.compactLayoutHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 14) {
                CompactSideEditor(
                    l10n: l10n,
                    side: .leading,
                    title: l10n.leftSide,
                    isOpen: $keepLeftOpen,
                    registry: registry)

                CompactSideEditor(
                    l10n: l10n,
                    side: .trailing,
                    title: l10n.rightSide,
                    isOpen: $keepRightOpen,
                    registry: registry)
            }

            HStack(spacing: 12) {
                Text(l10n.compactHeight)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(layout.contentHeight) },
                        set: { layout.setContentHeight(CGFloat($0)) }),
                    in: Double(NotchCompactLayout.minHeight)...Double(NotchCompactLayout.maxHeight),
                    step: 1)
                .frame(maxWidth: 220)

                Text("\(Int(layout.contentHeight.rounded())) pt")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)

                Spacer(minLength: 8)

                Text(l10n.aiMetric)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("AI metric", selection: $compactDisplayProvider) {
                    Text(l10n.autoOption).tag(Optional<TokenProviderKind>.none)
                    ForEach(compactProviderChoices) { provider in
                        Text(provider.displayName).tag(Optional(provider))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 148)
                .help(l10n.aiMetricHelp)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .onChange(of: keepLeftOpen) { _, open in
            layout.setPinned(open, side: .leading)
        }
        .onChange(of: keepRightOpen) { _, open in
            layout.setPinned(open, side: .trailing)
        }
        .onAppear {
            // Sync AppStorage toggles with store defaults once.
            keepLeftOpen = layout.isPinned(.leading)
            keepRightOpen = layout.isPinned(.trailing)
        }
    }
}

private struct CompactSideEditor: View {
    let l10n: L10n
    let side: NotchSide
    let title: String
    @Binding var isOpen: Bool
    @Bindable var registry: WidgetRegistry

    private var layout: NotchCompactLayoutStore { registry.layout }

    var body: some View {
        let _ = layout.revision
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $isOpen) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.checkbox)
                .help(isOpen ? l10n.sidePinnedHelp(title) : l10n.sideCollapsedHelp(title))

                Spacer()
                Text("\(Int(layout.maxWidth(for: side).rounded())) pt")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(layout.maxWidth(for: side)) },
                    set: { layout.setMaxWidth(CGFloat($0), for: side) }),
                in: Double(NotchCompactLayout.minWidth)...Double(NotchCompactLayout.maxWidth),
                step: 2)
            .disabled(!isOpen)
            .opacity(isOpen ? 1 : 0.45)

            Text(l10n.sideContent)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(registry.sortedByPriority, id: \.id) { widget in
                    let onSide = layout.isWidget(widget.id, on: side)
                    Toggle(isOn: Binding(
                        get: { onSide },
                        set: { layout.setWidget(widget.id, on: side, enabled: $0) }))
                    {
                        HStack(spacing: 5) {
                            Image(systemName: widget.settingsIconSystemName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(widget.settingsTitle)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .help(widget.settingsSubtitle)
                }
            }
            .disabled(!isOpen)
            .opacity(isOpen ? 1 : 0.45)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct WidgetVisibilitySettingsRow: View {
    let l10n: L10n
    @Bindable var registry: WidgetRegistry

    var body: some View {
        let _ = registry.visibilityRevision
        HStack(spacing: 12) {
            Label(l10n.widgetsRowTitle, systemImage: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Spacer(minLength: 10)

            ForEach(registry.sortedByPriority, id: \.id) { widget in
                WidgetVisibilityToggle(
                    widget: widget,
                    isVisible: Binding(
                        get: { registry.isWidgetVisible(widget) },
                        set: { registry.setWidget(id: widget.id, visible: $0) }),
                    canDisable: registry.canSetWidget(id: widget.id, visible: false))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct SystemMetricsSettingsRow: View {
    let l10n: L10n
    @State private var revision = 0

    var body: some View {
        let _ = revision
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l10n.systemMetricsTitle, systemImage: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text(l10n.systemMetricsHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                alignment: .leading,
                spacing: 6)
            {
                ForEach(SystemMetricKind.settingsOrder) { kind in
                    Toggle(isOn: Binding(
                        get: { SystemMetricPreferences.isEnabled(kind) },
                        set: { newValue in
                            if !newValue, !SystemMetricPreferences.canDisable(kind) {
                                return
                            }
                            SystemMetricPreferences.setEnabled(kind, newValue)
                            revision += 1
                        }))
                    {
                        HStack(spacing: 5) {
                            Image(systemName: kind.iconSystemName)
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 14)
                            Text(kind.label)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(
                        SystemMetricPreferences.isEnabled(kind)
                            && !SystemMetricPreferences.canDisable(kind))
                    .help(kind.label)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct WidgetVisibilityToggle: View {
    let widget: any NotchWidget
    @Binding var isVisible: Bool
    let canDisable: Bool

    var body: some View {
        Toggle(isOn: $isVisible) {
            HStack(spacing: 5) {
                Image(systemName: widget.settingsIconSystemName)
                    .font(.system(size: 10, weight: .semibold))
                Text(widget.settingsTitle)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isVisible && !canDisable)
        .help(widget.settingsSubtitle)
    }
}

private struct ProviderSidebarRow: View {
    let provider: TokenProviderKind
    let usage: ProviderUsage
    let isSelected: Bool
    let isEnabled: Bool
    let canDisable: Bool
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    ProviderIcon(provider: provider, size: 26)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            ProviderStatusDot(status: usage.status)
                        }

                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in onToggle(newValue) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!canDisable)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
        }
    }

    private var subtitle: String {
        if usage.status == .available {
            return "\(provider.capabilitySummary) · \(usage.dataCoverageText)"
        }
        return "\(usage.status.label) · \(provider.capabilitySummary)"
    }
}

private struct ProviderDetailHeader: View {
    let provider: TokenProviderKind
    let usage: ProviderUsage
    let isEnabled: Bool
    let canDisable: Bool
    let onRefresh: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ProviderIcon(provider: provider, size: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(provider.displayName)
                        .font(.system(size: 22, weight: .bold))
                    ProviderStatusBadge(status: usage.status)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(usage.status == .refreshing)

            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in onToggle(newValue) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!canDisable)
        }
    }

    private var subtitle: String {
        var parts = [usage.sourceSummaryText]
        if usage.versionText != "-" {
            parts.append(usage.versionText)
        }
        if let updatedText = usage.updatedText {
            parts.append(updatedText)
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProviderStateBanner: View {
    let usage: ProviderUsage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(usage.status.statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(usage.providerActionHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(usage.status.statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(usage.status.statusColor.opacity(0.18), lineWidth: 1)
        }
    }

    private var title: String {
        switch usage.status {
        case .available:
            return "Provider data is available"
        case .refreshing:
            return "Refreshing provider data"
        case .unsupported:
            return "Adapter is pending"
        case .unavailable:
            return "No provider data yet"
        case .idle:
            return "Waiting for first refresh"
        }
    }

    private var icon: String {
        switch usage.status {
        case .available:
            return "checkmark.seal"
        case .refreshing:
            return "arrow.clockwise"
        case .unsupported:
            return "hammer"
        case .unavailable:
            return "exclamationmark.triangle"
        case .idle:
            return "clock"
        }
    }
}

private struct ProviderCapabilityMatrix: View {
    let provider: TokenProviderKind
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capabilities")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 8) {
                capability("Live", enabled: provider.supportsLiveUsageSnapshot)
                capability("Cost", enabled: provider.supportsCostSnapshot)
                capability("Quota", enabled: provider.supportsQuotaSnapshot)
                capability("Data", enabled: usage.hasAnyUsageData)
            }

            Text(provider.expectedDataText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func capability(_ title: String, enabled: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? provider.tint : .secondary)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background((enabled ? provider.tint.opacity(0.13) : Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ProviderInfoGrid: View {
    let usage: ProviderUsage

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            infoRow("State", usage.status.label)
            infoRow("Source", usage.sourceText)
            infoRow("Strategy", usage.strategyID ?? "-")
            infoRow("Version", usage.versionText)
            infoRow("Updated", usage.updatedText ?? "-")
            infoRow("Account", usage.accountText)
            infoRow("Plan", usage.planText)
            infoRow("Coverage", usage.dataCoverageText)
        }
        .font(.system(size: 12))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }
}

private struct ProviderUsageDetail: View {
    let usage: ProviderUsage
    let displayMode: TokenUsageDisplayMode

    var body: some View {
        let sortedWindows = usage.sortedUsageWindows

        VStack(alignment: .leading, spacing: 10) {
            Text("Usage")
                .font(.system(size: 14, weight: .semibold))

            if !sortedWindows.isEmpty {
                VStack(spacing: 9) {
                    ForEach(sortedWindows) { window in
                        UsageWindowRow(
                            window: window,
                            provider: usage.provider,
                            displayMode: displayMode)
                    }
                }
            } else {
                NotchEmptyState(
                    icon: "tray",
                    title: "No session or quota window returned.",
                    subtitle: usage.providerActionHint,
                    tint: usage.status.statusColor)
            }

            if usage.hasTokenOrCostData {
                Divider().padding(.vertical, 2)
                ProviderCostDetail(usage: usage)
            }
        }
    }
}

private struct ProviderCostDetail: View {
    let usage: ProviderUsage

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            row("Session tokens", usage.sessionTokensText)
            row("Last 30 days", usage.last30DaysTokensText)
            row("Session cost", usage.sessionCostText)
            row("30d cost", usage.last30DaysCostText)
        }
        .font(.system(size: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .monospacedDigit()
        }
    }
}

// provider 圖示/狀態徽章/配額列 → App/Components/*（共用元件）
// provider 圖示/色票與狀態色 → App/Theme/ProviderAppearance.swift（單一真相）
