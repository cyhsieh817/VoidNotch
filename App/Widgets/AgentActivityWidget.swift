//
//  AgentActivityWidget.swift — AI agent lifecycle widget
//

import SwiftUI
import VoidNotchKit

public struct AgentActivityWidget: NotchWidget {
    public let id = "agent-activity"
    public let priority = 4

    let store: AgentActivityStore

    public init(store: AgentActivityStore) {
        self.store = store
    }

    public func compactView() -> AnyView {
        // When assigned to a compact side, show a small activity pill; otherwise zero-size.
        AnyView(AgentActivityCompactPill(store: store))
    }
    public func expandedView() -> AnyView { AnyView(AgentActivityExpandedView(store: store)) }
}

struct AgentActivityCompactPill: View {
    let store: AgentActivityStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 9, weight: .semibold))
            Text("\(store.activeEventCount)")
                .fontWeight(.semibold)
                .monospacedDigit()
            if store.attentionEventCount > 0 {
                Circle()
                    .fill(Theme.Colors.warning)
                    .frame(width: 5, height: 5)
            }
        }
        .font(Theme.Fonts.compact())
        .foregroundStyle(Theme.Colors.text)
        .frame(maxWidth: 52, alignment: .leading)
        .clipped()
        .help("Agent activity")
    }
}

struct AgentActivityExpandedView: View {
    let store: AgentActivityStore
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    private var l10n: L10n { L10n(rawValue: languageRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary

            if store.events.isEmpty {
                NotchEmptyState(
                    icon: "moon",
                    title: l10n.noAgentEvents,
                    subtitle: l10n.relayNotConnected)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.events) { event in
                        AgentActivityEventRow(event: event)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 390, maxWidth: 470)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(l10n.agentActivityTitle, systemImage: "waveform.path.ecg")
                .font(.headline)

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            SummaryPill(
                title: l10n.pillActive,
                value: "\(store.activeEventCount)",
                color: store.activeEventCount > 0 ? .blue : .secondary)
            SummaryPill(
                title: l10n.pillAttention,
                value: "\(store.attentionEventCount)",
                color: store.attentionEventCount > 0 ? .orange : .secondary)
            SummaryPill(
                title: l10n.pillRecent,
                value: "\(store.recentEventCount)",
                color: .white.opacity(0.82))
        }
    }
}

private struct AgentActivityEventRow: View {
    let event: AgentActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: event.provider.iconSystemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(event.provider.tint)
                    .frame(width: 24, height: 24)

                Circle()
                    .fill(event.status.dotColor)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.65), lineWidth: 1)
                    }
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(event.provider.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)

                    AgentActivityStatusPill(status: event.status)

                    Spacer(minLength: 8)

                    Text(event.ageText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                metadata
            }
        }
        .padding(10)
        .notchCard(border: event.status.borderColor)
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            if let detail = event.detail, !detail.isEmpty {
                Text(detail)
                    .lineLimit(1)
            }

            if let workspace = event.workspace, !workspace.isEmpty {
                Label(workspace, systemImage: "folder")
                    .lineLimit(1)
            }

            if let durationText = event.durationText {
                Label(durationText, systemImage: "timer")
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.secondary)
    }
}

private struct AgentActivityStatusPill: View {
    let status: AgentActivityStatus

    var body: some View {
        Label(status.label, systemImage: status.iconSystemName)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(status.textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(status.backgroundColor, in: Capsule())
    }
}

private extension AgentActivityProviderKind {
    var iconSystemName: String {
        switch self {
        case .codex: return "terminal"
        case .claude: return "cpu"
        case .antigravity: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .codex: return .blue
        case .claude: return .cyan
        case .antigravity: return .purple
        }
    }
}

private extension AgentActivityStatus {
    var iconSystemName: String {
        switch self {
        case .started: return "play.fill"
        case .running: return "bolt.fill"
        case .needsInput: return "questionmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .resourceLimit: return "exclamationmark.triangle.fill"
        case .stopped: return "stop.circle.fill"
        }
    }

    var dotColor: Color {
        switch self {
        case .started: return .blue
        case .running: return .green
        case .needsInput: return .orange
        case .completed: return .mint
        case .failed: return .red
        case .resourceLimit: return .yellow
        case .stopped: return .secondary
        }
    }

    var textColor: Color {
        switch self {
        case .failed:
            return .red
        case .needsInput, .resourceLimit:
            return .orange
        case .started, .running:
            return .blue
        case .completed:
            return .green
        case .stopped:
            return .secondary
        }
    }

    var backgroundColor: Color {
        textColor.opacity(0.14)
    }

    var borderColor: Color {
        switch self {
        case .failed:
            return .red.opacity(0.24)
        case .needsInput, .resourceLimit:
            return .orange.opacity(0.26)
        case .started, .running:
            return .blue.opacity(0.2)
        case .completed:
            return .green.opacity(0.16)
        case .stopped:
            return .white.opacity(0.08)
        }
    }
}
