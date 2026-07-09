//
//  AgentActivityEvent.swift — Agent models, protocol, and static providers
//
//  Moved from App/Monitors/AgentActivityStore.swift into VoidNotchKit
//  so the model layer is available to the Kit without app-layer imports.
//

import Foundation
import Observation

public enum AgentActivityProviderKind: String, CaseIterable, Sendable, Identifiable {
    case codex
    case claude
    case antigravity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .antigravity: return "Gemini (Agy)"
        }
    }

    public var compactName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .antigravity: return "Agy"
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

    public init(
        id: UUID = UUID(),
        provider: AgentActivityProviderKind,
        status: AgentActivityStatus,
        title: String,
        detail: String? = nil,
        workspace: String? = nil,
        occurredAt: Date = Date(),
        durationSeconds: TimeInterval? = nil)
    {
        self.id = id
        self.provider = provider
        self.status = status
        self.title = title
        self.detail = detail
        self.workspace = workspace
        self.occurredAt = occurredAt
        self.durationSeconds = durationSeconds
    }

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

