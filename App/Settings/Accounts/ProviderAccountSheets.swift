import SwiftUI
import VoidNotchKit

struct ProviderAccountImportSheet: View {
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

struct ProviderAccountExportSheet: View {
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
