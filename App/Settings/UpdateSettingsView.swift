//
//  UpdateSettingsView.swift — 軟體更新檢查與安裝
//

import Foundation
import SwiftUI
import VoidNotchKit

@MainActor
struct UpdateSettingsView: View {
    let updateCheckStore: UpdateCheckStore
    let l10n: L10n

    @State private var selfUpdateController: SelfUpdateController

    init(updateCheckStore: UpdateCheckStore, l10n: L10n) {
        self.updateCheckStore = updateCheckStore
        self.l10n = l10n
        _selfUpdateController = State(initialValue: SelfUpdateController())
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            updateSection
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 常駐「軟體更新」小節：下載安裝失敗仍保留手動下載退路。
    @ViewBuilder
    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.updateSectionTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            updateInstallStatus

            if updateCheckStore.isChecking {
                ProgressView()
                    .controlSize(.mini)
            } else if let availableUpdate = updateCheckStore.availableUpdate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(l10n.updateAvailable(availableUpdate.version))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button(l10n.updateInstallNow) {
                            selfUpdateController.install(availableUpdate)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .disabled(selfUpdateController.state.isBusy)
                    }

                    if let url = URL(string: availableUpdate.url) {
                        Link(l10n.updateManualDownload, destination: url)
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
    }

    @ViewBuilder
    private var updateInstallStatus: some View {
        switch selfUpdateController.state {
        case .idle:
            EmptyView()
        case .downloading:
            updateProgress(l10n.updateDownloading)
        case .extracting:
            updateProgress(l10n.updateExtracting)
        case .verifying:
            updateProgress(l10n.updateVerifying)
        case .installing:
            updateProgress(l10n.updateInstalling)
        case let .failed(error):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(l10n.updateError(error))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func updateProgress(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
