import AppKit
import SwiftUI
import VoidNotchKit

struct ProviderAccountSection: View {
    let provider: TokenProviderKind
    let accounts: [ProviderAccount]
    let accountUsages: [ProviderAccountUsage]
    let errorMessage: String?
    let onRefresh: () -> Void
    let onImport: () -> Void
    let onImportRaw: (ProviderAccountImport) -> Void
    let onSelect: (ProviderAccount) -> Void
    let onApplyToCLI: (ProviderAccount) -> Void
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
                                onApplyToCLI: { onApplyToCLI(account) },
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
