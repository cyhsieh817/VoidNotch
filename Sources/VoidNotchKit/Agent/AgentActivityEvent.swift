//
//  AgentActivityEvent.swift — Agent models, protocol, and static providers
//
//  Moved from App/Monitors/AgentActivityStore.swift into VoidNotchKit
//  so the model layer is available to the Kit without app-layer imports.
//

import Foundation
import Observation
import VoidNotchSpeechKit

public enum AgentActivityProviderKind: String, CaseIterable, Sendable, Identifiable {
    case codex
    case claude
    case antigravity
    case grok
    case pi
    case hermes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .antigravity: return "Gemini (Agy)"
        case .grok: return "Grok"
        case .pi: return "pi"
        case .hermes: return "Hermes"
        }
    }

    public var compactName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .antigravity: return "Agy"
        case .grok: return "Grok"
        case .pi: return "pi"
        case .hermes: return "Hermes"
        }
    }
}

public enum AgentActivityStatus: String, Sendable {
    case started
    case running
    case needsInput
    case completed
    case failed
    case resourceLimit
    case stopped

    public var label: String {
        switch self {
        case .started: return "Started"
        case .running: return "Running"
        case .needsInput: return "Needs input"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .resourceLimit: return "Resource limit"
        case .stopped: return "Stopped"
        }
    }

    public var compactLabel: String {
        switch self {
        case .started: return "start"
        case .running: return "run"
        case .needsInput: return "input"
        case .completed: return "done"
        case .failed: return "error"
        case .resourceLimit: return "limit"
        case .stopped: return "stop"
        }
    }

    public var isAttentionState: Bool {
        switch self {
        case .needsInput, .failed, .resourceLimit:
            return true
        case .started, .running, .completed, .stopped:
            return false
        }
    }

    public var isActiveState: Bool {
        switch self {
        case .started, .running:
            return true
        case .needsInput, .completed, .failed, .resourceLimit, .stopped:
            return false
        }
    }

    /// 一般提醒的取代優先序；可作答 input 由 alert flow 另行視為最高優先級。
    public var alertPriority: Int {
        switch self {
        case .needsInput, .failed, .resourceLimit:
            return 2
        case .started, .completed:
            return 1
        case .running, .stopped:
            return 0
        }
    }
}

public struct AgentInputRequest: Sendable, Equatable {
    public let requestID: UUID
    public let questions: [AgentInputQuestion]
    public init(requestID: UUID, questions: [AgentInputQuestion]) { self.requestID = requestID; self.questions = questions }
}

public enum AgentNavigationSourceSurface: String, Sendable, Equatable {
    case ghostty
    case appleTerminal = "apple_terminal"
    case iterm
    case claudeDesktop = "claude_desktop"
    case codexApp = "codex_app"
    case unknown
}

/// JSONL 裡的來源導覽資訊。所有欄位都來自不受信任的 hook payload；App 端仍須重新驗證。
public struct AgentNavigationTarget: Sendable, Equatable {
    public let sourceSurface: AgentNavigationSourceSurface
    public let sessionID: String?
    public let tmuxSocket: String?
    public let tmuxPane: String?
    public let tmuxWindow: String?
    public let tmuxSession: String?
    public let tmuxClientTTY: String?

    public init(
        sourceSurface: AgentNavigationSourceSurface,
        sessionID: String? = nil,
        tmuxSocket: String? = nil,
        tmuxPane: String? = nil,
        tmuxWindow: String? = nil,
        tmuxSession: String? = nil,
        tmuxClientTTY: String? = nil)
    {
        self.sourceSurface = sourceSurface
        self.sessionID = sessionID
        self.tmuxSocket = tmuxSocket
        self.tmuxPane = tmuxPane
        self.tmuxWindow = tmuxWindow
        self.tmuxSession = tmuxSession
        self.tmuxClientTTY = tmuxClientTTY
    }

    /// unknown 來源只有在具備 tmux 目標時才可導覽；已知來源可至少啟用固定來源 App。
    public var isActionable: Bool {
        sourceSurface != .unknown
            || (tmuxSocket != nil && (tmuxPane != nil || tmuxWindow != nil || tmuxSession != nil))
    }
}

public struct AgentActivityEvent: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var provider: AgentActivityProviderKind
    public var status: AgentActivityStatus
    public var title: String
    public var detail: String?
    public var workspace: String?
    public var occurredAt: Date
    public var durationSeconds: TimeInterval?
    public var inputRequest: AgentInputRequest?
    public var navigation: AgentNavigationTarget?

    /// 相容較語意化的呼叫端命名；JSONL 欄位仍稱為 `navigation`。
    public var navigationTarget: AgentNavigationTarget? {
        get { navigation }
        set { navigation = newValue }
    }

    public init(
        id: UUID = UUID(),
        provider: AgentActivityProviderKind,
        status: AgentActivityStatus,
        title: String,
        detail: String? = nil,
        workspace: String? = nil,
        occurredAt: Date = Date(),
        durationSeconds: TimeInterval? = nil,
        inputRequest: AgentInputRequest? = nil,
        navigation: AgentNavigationTarget? = nil)
    {
        self.id = id
        self.provider = provider
        self.status = status
        self.title = title
        self.detail = detail
        self.workspace = workspace
        self.occurredAt = occurredAt
        self.durationSeconds = durationSeconds
        self.inputRequest = inputRequest
        self.navigation = navigation
    }

    /// 這則事件能否在瀏海直接作答。判準是「有沒有帶問答請求」，不是「是哪一家 agent」——
    /// 任何走同一套檔案 broker 協議的 provider（Claude 走 relay、pi 走 extension）都該能答。
    public var isAnswerable: Bool { inputRequest != nil }

    public var compactText: String {
        "\(provider.compactName) \(status.compactLabel)"
    }

    public var ageText: String {
        Self.elapsedText(from: occurredAt, to: Date())
    }

    public var durationText: String? {
        let activeDuration: TimeInterval?
        if status.isActiveState {
            activeDuration = Date().timeIntervalSince(occurredAt)
        } else {
            activeDuration = nil
        }

        guard let seconds = durationSeconds ?? activeDuration else { return nil }
        return Self.durationText(seconds)
    }

    private static func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start).rounded()))
        if seconds < 60 { return "now" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }

        return "\(hours / 24)d ago"
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        if rounded < 60 { return "\(rounded)s" }

        let minutes = rounded / 60
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
    }
}

public protocol AgentActivityProviding: Sendable {
    func fetchEvents() async -> [AgentActivityEvent]
}

public struct EmptyAgentActivityProvider: AgentActivityProviding {
    public init() {}

    public func fetchEvents() async -> [AgentActivityEvent] {
        []
    }
}

public struct StaticAgentActivityProvider: AgentActivityProviding {
    private let snapshots: [AgentActivityEvent]

    public init(_ snapshots: [AgentActivityEvent]) {
        self.snapshots = snapshots
    }

    public func fetchEvents() async -> [AgentActivityEvent] {
        snapshots
    }
}
