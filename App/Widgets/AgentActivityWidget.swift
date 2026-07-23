//
//  AgentActivityWidget.swift — AI agent lifecycle widget
//

import SwiftUI
import AppKit
import Darwin
import VoidNotchKit

public struct AgentActivityWidget: NotchWidget {
    public let id = "agent-activity"
    public let priority = 4

    let store: AgentActivityStore
    /// 接通狀態的來源。傳 nil 就不顯示診斷區塊（預覽／測試用）。
    let connections: (@MainActor @Sendable () -> [AgentConnectionState])?

    public init(
        store: AgentActivityStore,
        connections: (@MainActor @Sendable () -> [AgentConnectionState])? = nil
    ) {
        self.store = store
        self.connections = connections
    }

    public func compactView() -> AnyView {
        // When assigned to a compact side, show a small activity pill; otherwise zero-size.
        AnyView(AgentActivityCompactPill(store: store))
    }
    public func expandedView() -> AnyView {
        AnyView(AgentActivityExpandedView(store: store, connections: connections))
    }
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
    var connections: (@MainActor @Sendable () -> [AgentConnectionState])? = nil
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    private var l10n: L10n { L10n(rawValue: languageRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary

            if let connections {
                AgentConnectionSection(states: connections(), l10n: l10n)
            }

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

            if store.isRefreshing, store.lastRefreshedAt == nil {
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

/// 接通狀態：哪些 agent 會把動靜送進瀏海、哪些只是裝了但不會觸發。
///
/// 設計原則是「不隱瞞壞消息」——`conflict`（設定在、卻不會跑）必須用警示色單獨標出，
/// 混進「已接通」裡會讓使用者以為好了，然後永遠等不到通知。
private struct AgentConnectionSection: View {
    let states: [AgentConnectionState]
    let l10n: L10n

    private var needsAttention: Int { AgentConnectionDiagnostics.attentionCount(states) }

    var body: some View {
        if !states.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(l10n.connectionSectionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if needsAttention > 0 {
                        Text(l10n.connectionPendingCount(needsAttention))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.22), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }

                ForEach(states) { state in
                    AgentConnectionRow(state: state, l10n: l10n)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct AgentConnectionRow: View {
    let state: AgentConnectionState
    let l10n: L10n

    /// conflict 與 notInstalled 都不是「好了」。只有 installed 才給綠燈。
    private var icon: (name: String, tint: Color) {
        switch state.hook {
        case .installed:
            return ("checkmark.circle.fill", .green)
        case .conflict:
            return ("exclamationmark.triangle.fill", .orange)
        case .notInstalled:
            return ("circle.dashed", .secondary)
        case .agentAbsent:
            return ("minus.circle", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon.name)
                .font(.caption)
                .foregroundStyle(icon.tint)
                .frame(width: 14)
                .id(icon.name)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.15), value: state.hook)

            Text(state.provider.displayName)
                .font(.caption.weight(.medium))
                .frame(width: 60, alignment: .leading)

            Text(state.detail(l10n))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .help(state.detail(l10n))
    }
}

private struct AgentActivityEventRow: View {
    let event: AgentActivityEvent

    @ViewBuilder
    var body: some View {
        if event.navigation?.isActionable == true {
            Button {
                AgentActivityNavigation.open(event.navigation)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
        } else {
            rowContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint)
        }
    }

    private var rowContent: some View {
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

    private var accessibilityLabel: String {
        "\(event.provider.displayName) \(event.status.label): \(event.title)"
    }

    private var accessibilityHint: String {
        event.navigation?.isActionable == true
            ? "Open the recorded source app or terminal"
            : "Source navigation unavailable"
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

/// 來源導覽的唯一 App 端入口。payload 不可形成 shell command、URL 或任意 bundle identifier。
@MainActor
enum AgentActivityNavigation {
    private struct SourceApplication {
        let bundleIdentifier: String
        let name: String
    }

    static func open(_ target: AgentNavigationTarget?) {
        guard let target, target.isActionable else { return }

        if supportsTmux(for: target.sourceSurface) {
            activateSourceApp(for: target.sourceSurface)
            guard let socket = validatedSocketPath(target.tmuxSocket), hasTMuxIdentifier(target) else {
                return
            }

            Task { @MainActor in
                let didNavigate = await Task.detached(priority: .userInitiated) {
                    navigateTmux(target: target, socket: socket)
                }.value
                if !didNavigate {
                    // tmux 失敗時維持已知來源 App 的安全 fallback，不嘗試 payload 內的任意 URL。
                    activateSourceApp(for: target.sourceSurface)
                }
            }
            return
        }

        // Claude Desktop / Codex App 此迭代只做固定 App activation，不做 deep link。
        activateSourceApp(for: target.sourceSurface)
    }

    private static func supportsTmux(for surface: AgentNavigationSourceSurface) -> Bool {
        switch surface {
        case .ghostty, .appleTerminal, .iterm:
            return true
        case .claudeDesktop, .codexApp:
            return false
        case .unknown:
            // unknown 沒有 App fallback，但若 payload 帶完整 tmux 目標仍可安全嘗試 tmux。
            return true
        }
    }

    private static func sourceApplication(
        for surface: AgentNavigationSourceSurface) -> SourceApplication?
    {
        switch surface {
        case .ghostty:
            return SourceApplication(bundleIdentifier: "com.mitchellh.ghostty", name: "Ghostty")
        case .appleTerminal:
            return SourceApplication(bundleIdentifier: "com.apple.Terminal", name: "Terminal")
        case .iterm:
            return SourceApplication(bundleIdentifier: "com.googlecode.iterm2", name: "iTerm")
        case .claudeDesktop:
            return SourceApplication(
                bundleIdentifier: "com.anthropic.claudefordesktop",
                name: "Claude Desktop")
        case .codexApp:
            return SourceApplication(bundleIdentifier: "com.openai.codex", name: "Codex")
        case .unknown:
            return nil
        }
    }

    private static func activateSourceApp(for surface: AgentNavigationSourceSurface) {
        guard let application = sourceApplication(for: surface) else { return }
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: application.bundleIdentifier).first
        {
            running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: application.bundleIdentifier)
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration,
            completionHandler: nil)
    }

    nonisolated private static func navigateTmux(
        target: AgentNavigationTarget,
        socket: String) -> Bool
    {
        guard let executable = fixedTmuxExecutable() else { return false }
        let pane = validTmuxPane(target.tmuxPane)
        let window = validTmuxWindow(target.tmuxWindow)
        let session = validTmuxSession(target.tmuxSession)
        guard pane != nil || window != nil || session != nil else { return false }

        let queryTarget = pane ?? window ?? session
        guard let queryTarget else { return false }
        let query = runTmux(
            executable: executable,
            socket: socket,
            arguments: [
                "display-message", "-p", "-t", queryTarget,
                "#{session_name}\t#{window_id}\t#{pane_id}",
            ])
        guard query.success else { return false }

        let fields = query.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 3,
              let availableSession = validTmuxSession(String(fields[0])),
              let availableWindow = validTmuxWindow(String(fields[1])),
              let availablePane = validTmuxPane(String(fields[2]))
        else { return false }

        // 先對照 display-message 回報的完整 session/window/pane，避免 stale 或毒 payload 被選取。
        if let session, session != availableSession { return false }
        if let window, window != availableWindow { return false }
        if let pane, pane != availablePane { return false }

        let clientTTY = validTmuxClientTTY(target.tmuxClientTTY)
        if let clientTTY {
            guard runTmux(
                executable: executable,
                socket: socket,
                arguments: ["switch-client", "-c", clientTTY, "-t", availableSession]).success
            else { return false }
        }

        // 沒有有效 recorded client tty 時只能靠 select-window/select-pane；這是 best-effort。
        guard runTmux(
            executable: executable,
            socket: socket,
            arguments: ["select-window", "-t", availableWindow]).success
        else { return false }

        return runTmux(
            executable: executable,
            socket: socket,
            arguments: ["select-pane", "-t", availablePane]).success
    }

    nonisolated private static func hasTMuxIdentifier(_ target: AgentNavigationTarget) -> Bool {
        validTmuxPane(target.tmuxPane) != nil
            || validTmuxWindow(target.tmuxWindow) != nil
            || validTmuxSession(target.tmuxSession) != nil
    }

    nonisolated private static func fixedTmuxExecutable() -> String? {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    nonisolated private static func validatedSocketPath(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/"), isTemporaryPath(path) else { return nil }
        let resolved = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        guard isTemporaryPath(resolved) else { return nil }

        var fileInfo = stat()
        guard lstat(resolved, &fileInfo) == 0,
              (fileInfo.st_mode & S_IFMT) == S_IFSOCK,
              fileInfo.st_uid == getuid()
        else { return nil }
        return resolved
    }

    nonisolated private static func isTemporaryPath(_ path: String) -> Bool {
        path == "/tmp" || path.hasPrefix("/tmp/")
            || path == "/private/tmp" || path.hasPrefix("/private/tmp/")
    }

    nonisolated private static func validTmuxPane(_ value: String?) -> String? {
        validTmuxIdentifier(value, pattern: #"^%[0-9]+$"#)
    }

    nonisolated private static func validTmuxWindow(_ value: String?) -> String? {
        validTmuxIdentifier(value, pattern: #"^@[0-9]+$"#)
    }

    nonisolated private static func validTmuxClientTTY(_ value: String?) -> String? {
        validTmuxIdentifier(value, pattern: #"^/dev/tty[A-Za-z0-9._-]+$"#)
    }

    nonisolated private static func validTmuxIdentifier(
        _ value: String?,
        pattern: String) -> String?
    {
        guard let value,
              !value.isEmpty,
              value.range(of: pattern, options: .regularExpression) != nil
        else { return nil }
        return value
    }

    nonisolated private static func validTmuxSession(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              value.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return value
    }

    nonisolated private static func runTmux(
        executable: String,
        socket: String,
        arguments: [String]) -> (success: Bool, stdout: String)
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-S", socket] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (false, "")
        }

        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 2,
            execute: timeout)
        process.waitUntilExit()
        timeout.cancel()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus == 0,
            String(data: data, encoding: .utf8) ?? "")
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
        case .grok: return "lightbulb"
        case .pi: return "circle.fill"
        case .hermes: return "wand.and.stars"
        }
    }

    var tint: Color {
        switch self {
        case .codex: return .blue
        case .claude: return .cyan
        case .antigravity: return .purple
        case .grok: return .orange
        case .pi: return .red
        case .hermes: return .green
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
