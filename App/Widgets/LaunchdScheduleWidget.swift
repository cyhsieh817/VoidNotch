//
//  LaunchdScheduleWidget.swift — launchd 排程任務 Scheduled 分頁
//

import SwiftUI
import VoidNotchKit

public struct LaunchdScheduleWidget: NotchWidget {
    public let id = "launchd-schedule"
    public let priority = 2
    public var hasCompactContent: Bool { false }

    let store: LaunchdScheduleStore

    public init(store: LaunchdScheduleStore) {
        self.store = store
    }

    public func compactView() -> AnyView {
        AnyView(EmptyView())
    }

    public func expandedView() -> AnyView {
        AnyView(LaunchdScheduleExpandedView(store: store))
    }
}

// MARK: - Expanded

struct LaunchdScheduleExpandedView: View {
    let store: LaunchdScheduleStore
    var listMaxHeight: CGFloat = 220
    var allowsRemoval: Bool = false
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue
    @State private var selectedPhase: LaunchdJobPhase = .run
    @State private var pendingRemoval: LaunchdJob?
    @State private var removalError: String?

    private var l10n: L10n { L10n(rawValue: languageRaw) }

    private var isZhHant: Bool {
        l10n.language == .zhTW
    }

    private var phaseJobs: [LaunchdJob] {
        store.jobs(in: selectedPhase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            phasePills
            jobList
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            Task { await store.refresh() }
        }
        .confirmationDialog(
            l10n.schedRemoveConfirmTitle(pendingRemoval?.label ?? ""),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval)
        { job in
            Button(l10n.schedRemoveConfirm, role: .destructive) {
                pendingRemoval = nil
                Task {
                    let result = await store.removeJob(job)
                    if case let .failure(error) = result {
                        removalError = removalErrorReason(error)
                    }
                }
            }
            Button(l10n.commonCancel, role: .cancel) {
                pendingRemoval = nil
            }
        } message: { _ in
            Text(l10n.schedRemoveConfirmMessage)
        }
        .alert(
            l10n.schedRemoveFailed(removalError ?? ""),
            isPresented: Binding(
                get: { removalError != nil },
                set: { if !$0 { removalError = nil } }))
        {
            Button(l10n.commonCancel, role: .cancel) {
                removalError = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Label(l10n.tabScheduled, systemImage: "calendar.badge.clock")
                .font(.headline)

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Group {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.text.opacity(0.85))
            .disabled(store.isRefreshing)
            .help(l10n.schedRefresh)
        }
    }

    // MARK: Phase pills

    private var phasePills: some View {
        HStack(spacing: 6) {
            ForEach(LaunchdJobPhase.allCases, id: \.self) { phase in
                let count = store.jobs(in: phase).count
                let selected = selectedPhase == phase
                Button {
                    selectedPhase = phase
                } label: {
                    Text("\(phaseTitle(phase)) \(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Theme.Colors.text : Theme.Colors.text.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selected ? Theme.Colors.cpu.opacity(0.32) : Color.clear,
                            in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(
                                    selected
                                        ? Theme.Colors.cpu.opacity(0.55)
                                        : Color.white.opacity(0.14),
                                    lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Job list

    @ViewBuilder
    private var jobList: some View {
        if phaseJobs.isEmpty {
            Text(emptyText(selectedPhase))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72)
                .multilineTextAlignment(.center)
        } else {
            // 外層 NotchExpandedPanel 已有 ScrollView；此處再封一層並限高，
            // 讓 header／pills 固定、清單在有限高度內自捲（同 Agent 展開面板高度紀律）。
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 6) {
                    ForEach(phaseJobs, id: \.id) { job in
                        LaunchdJobRow(
                            job: job,
                            zhHant: isZhHant,
                            l10n: l10n,
                            showsRemoval: allowsRemoval && (selectedPhase != .archived || job.isZombie),
                            canRemove: LaunchdJobRetirement.isRemovable(
                                plistPath: job.plistPath,
                                phase: job.phase,
                                homeLaunchAgents: store.homeLaunchAgentsURL,
                                isZombie: job.isZombie),
                            onRemove: { pendingRemoval = job })
                    }
                }
            }
            .frame(maxHeight: listMaxHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func phaseTitle(_ phase: LaunchdJobPhase) -> String {
        switch phase {
        case .run: return l10n.schedPhaseRun
        case .paused: return l10n.schedPhasePaused
        case .archived: return l10n.schedPhaseArchived
        }
    }

    private func emptyText(_ phase: LaunchdJobPhase) -> String {
        switch phase {
        case .run: return l10n.schedEmptyRun
        case .paused: return l10n.schedEmptyPaused
        case .archived: return l10n.schedEmptyArchived
        }
    }

    private func removalErrorReason(_ error: RemovalError) -> String {
        switch error {
        case .notRemovable:
            return l10n.schedRemoveSystemDirHint
        case let .unloadFailed(reason), let .renameFailed(reason):
            return reason
        }
    }
}

// MARK: - Row

private struct LaunchdJobRow: View {
    let job: LaunchdJob
    let zhHant: Bool
    let l10n: L10n
    let showsRemoval: Bool
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.Colors.text)

                HStack(spacing: 6) {
                    Text(job.harness.displayName)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.text.opacity(0.78))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.08), in: Capsule())

                    Text(LaunchdScheduleFormatter.text(for: job.schedule, zhHant: zhHant))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if job.phase == .archived && job.isZombie {
                    Text(l10n.schedZombieWarning)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                if let pid = job.pid {
                    Text("PID \(pid)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let exitStatus = job.lastExitStatus, exitStatus != 0 {
                    Text("exit \(exitStatus)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
            }

            if showsRemoval {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.7))
                .disabled(!canRemove)
                .help(canRemove ? l10n.schedRemove : l10n.schedRemoveSystemDirHint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(job.programSummary + "\n" + job.plistPath)
    }

    /// 狀態圓點：exit 非 0 覆蓋為紅；否則依 phase／pid。
    private var statusDotColor: Color {
        if let exitStatus = job.lastExitStatus, exitStatus != 0 {
            return .red
        }
        switch job.phase {
        case .run:
            return job.pid != nil ? .green : Color.secondary
        case .paused:
            return .yellow
        case .archived:
            return Color.secondary.opacity(0.45)
        }
    }
}
