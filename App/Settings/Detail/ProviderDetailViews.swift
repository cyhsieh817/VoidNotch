import SwiftUI
import VoidNotchKit

struct ProviderSidebarRow: View {
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

struct ProviderDetailHeader: View {
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

struct ProviderStateBanner: View {
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

struct ProviderCapabilityMatrix: View {
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

struct ProviderInfoGrid: View {
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

struct ProviderUsageDetail: View {
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

struct ProviderCostDetail: View {
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
