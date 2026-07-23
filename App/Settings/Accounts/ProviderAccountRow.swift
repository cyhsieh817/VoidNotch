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
