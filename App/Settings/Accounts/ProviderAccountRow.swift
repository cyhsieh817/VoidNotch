import SwiftUI
import VoidNotchKit

struct ProviderAccountRow: View {
    let account: ProviderAccount
    let usage: ProviderAccountUsage?
    let tint: Color
    let onSelect: () -> Void
    let onApplyToCLI: () -> Void
    let onSetDisabled: (Bool) -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

                if usage != nil {
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isExpanded ? "Hide quota windows" : "Show remaining quota by window")
                }

                Button(action: onApplyToCLI) {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(account.isDisabled)
                .help("Apply this account to the agy CLI login (takes effect next time agy starts)")

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

            if isExpanded, let usage {
                expandedQuotaDetail(for: usage)
                    .padding(.top, 8)
                    .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(account.isActive ? tint.opacity(0.10) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(account.isActive ? tint.opacity(0.20) : Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func expandedQuotaDetail(for usage: ProviderAccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(usage.usage.usageWindows) { window in
                usageWindowDetail(window)
            }

            if let errorMessage = usage.usage.errorMessage,
               !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func usageWindowDetail(_ window: ProviderUsageWindow) -> some View {
        let remainingColor = remainingQuotaColor(for: window)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(window.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(window.usageKnown ? "\(window.remainingPercent)% left" : "—")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(window.usageKnown ? remainingColor : Color.secondary)

                if let resetText = window.resetText {
                    Text(resetText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.10))
                    Capsule()
                        .fill(remainingColor)
                        .frame(
                            width: proxy.size.width
                                * CGFloat(min(max(window.usageKnown ? window.remainingPercent : 0, 0), 100))
                                / 100)
                }
            }
            .frame(height: 4)
        }
    }

    /// 剩餘 >50% 綠、20–50% 黃、<20% 紅；未知用量用 secondary。
    private func remainingQuotaColor(for window: ProviderUsageWindow) -> Color {
        guard window.usageKnown else { return .secondary }
        if window.remainingPercent > 50 {
            return .green
        }
        if window.remainingPercent >= 20 {
            return .yellow
        }
        return .red
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
