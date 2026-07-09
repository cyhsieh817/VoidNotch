//
//  TokenWidget.swift — AI Provider Token 用量 widget
//
//  ⚠️ Xcode app target 專屬。
//  透過 TokenStore 消費 CodexBarCore adapter，UI 不直接 import 第三方型別。
//

import SwiftUI
import VoidNotchKit

public struct TokenWidget: NotchWidget {
    public let id = "token"
    public let priority = 5

    let store: TokenStore
    let agentStore: AgentActivityStore

    public init(store: TokenStore, agentStore: AgentActivityStore) {
        self.store = store
        self.agentStore = agentStore
    }

    public func compactView() -> AnyView { AnyView(AISummaryCapsule(tokenStore: store, agentStore: agentStore)) }
    public func expandedView() -> AnyView { AnyView(TokenExpandedView(store: store)) }
}

struct AISummaryCapsule: View {
    let tokenStore: TokenStore
    let agentStore: AgentActivityStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: TokenStore.compactRotationInterval)) { timeline in
            let usage = tokenStore.compactDisplayUsage(at: timeline.date)
            HStack(spacing: 4) {
                Image(systemName: usage?.provider.iconSystemName ?? "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(usage?.provider.tint ?? Theme.Colors.text)
                ViewThatFits(in: .horizontal) {
                    Text(displayText(for: usage))
                    Text(usage?.compactText(for: tokenStore.usageDisplayMode) ?? "-")
                    Circle().fill(statusColor(for: usage)).frame(width: 6, height: 6)
                }
                Circle().fill(statusColor(for: usage)).frame(width: 6, height: 6)
            }
            .font(Theme.Fonts.compact())
            .foregroundStyle(Theme.Colors.text)
            .monospacedDigit()
            .frame(maxWidth: 140, alignment: .leading)
            .clipped()
            .help(usage?.provider.displayName ?? "Auto")
        }
    }

    private func displayText(for usage: ProviderUsage?) -> String {
        guard let usage else { return "-" }
        return "\(usage.provider.compactName) \(usage.compactText(for: tokenStore.usageDisplayMode))"
    }

    private func statusColor(for usage: ProviderUsage?) -> Color {
        if tokenStore.attentionProviderCount > 0 || agentStore.attentionEventCount > 0 {
            return Theme.Colors.warning
        }
        if agentStore.activeEventCount > 0 {
            return Theme.Colors.cpu      // 活躍色(沿用 Theme 既有藍)
        }
        return usage?.status.dotColor ?? .secondary
    }
}

struct TokenExpandedView: View {
    let store: TokenStore
    @State private var selectedProvider: TokenProviderKind?
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ProviderBookmarkBar(
                providers: store.providers,
                selectedProvider: selectedUsage?.provider,
                onSelect: { selectedProvider = $0 })

            if let selectedUsage {
                TokenProviderUsageCard(
                    provider: selectedUsage,
                    displayMode: store.usageDisplayMode)
            }
        }
        .padding(14)
        .frame(minWidth: 390, maxWidth: 470)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(L10n(rawValue: languageRaw).modelUsageTitle, systemImage: "chart.bar.xaxis")
                .font(.headline)

            Spacer()

            Picker(
                "Display",
                selection: Binding(
                    get: { store.usageDisplayMode },
                    set: { store.setUsageDisplayMode($0) }))
            {
                ForEach(TokenUsageDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 116)

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var selectedUsage: ProviderUsage? {
        if let selectedProvider,
           let usage = store.providers.first(where: { $0.provider == selectedProvider })
        {
            return usage
        }
        return store.providers.first
    }
}

private struct ProviderBookmarkBar: View {
    let providers: [ProviderUsage]
    let selectedProvider: TokenProviderKind?
    let onSelect: (TokenProviderKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(providers) { usage in
                    ProviderBookmarkButton(
                        usage: usage,
                        isSelected: selectedProvider == usage.provider,
                        onSelect: { onSelect(usage.provider) })
                }
            }
        }
        .frame(height: 30)
    }
}

private struct ProviderBookmarkButton: View {
    let usage: ProviderUsage
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: usage.provider.iconSystemName)
                    .font(.system(size: 10, weight: .semibold))
                Text(usage.provider.shortDisplayName)
                    .lineLimit(1)
                Circle()
                    .fill(usage.status.dotColor)
                    .frame(width: 5, height: 5)
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? usage.provider.tint : .white.opacity(0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? usage.provider.tint.opacity(0.45) : .white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(usage.provider.displayName)
    }

    private var background: some ShapeStyle {
        isSelected ? usage.provider.tint.opacity(0.18) : .white.opacity(0.06)
    }
}

private struct TokenProviderUsageCard: View {
    let provider: ProviderUsage
    let displayMode: TokenUsageDisplayMode
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let sortedWindows = provider.sortedUsageWindows
        let l10n = L10n(rawValue: languageRaw)

        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                ProviderIcon(provider: provider.provider)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        ProviderStatusBadge(status: provider.status)
                    }

                    Text(provider.sourceSummaryText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(provider.primaryMetricText(for: displayMode))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(provider.updatedText ?? l10n.notRefreshed)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !sortedWindows.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sortedWindows) { window in
                        UsageWindowRow(
                            window: window,
                            provider: provider.provider,
                            displayMode: displayMode)
                    }
                }
            }

            if provider.hasTokenOrCostData {
                TokenCostSummary(provider: provider)
            } else if sortedWindows.isEmpty {
                NotchEmptyState(
                    icon: "tray",
                    title: provider.status == .unsupported ? l10n.adapterPending : l10n.noUsageWindow,
                    subtitle: provider.providerActionHint,
                    tint: provider.status.statusColor)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: provider.status == .available ? "checkmark.seal" : "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(provider.status.statusColor)
                    .frame(width: 14)
                Text(provider.statusDetailText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .notchCard(
            fillOpacity: provider.status == .available ? 0.075 : 0.045,
            border: provider.status.borderColor,
            cornerRadius: Theme.Metrics.cornerRadius)
    }
}

private struct TokenCostSummary: View {
    let provider: ProviderUsage

    var body: some View {
        HStack(spacing: 10) {
            metric(title: "Session", value: provider.sessionTokensText)
            metric(title: "30d", value: provider.last30DaysTokensText)
            metric(title: "Session cost", value: provider.sessionCostText)
            metric(title: "30d cost", value: provider.last30DaysCostText)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// provider 圖示/色票與狀態色 → App/Theme/ProviderAppearance.swift（單一真相）
