import Foundation

public enum TokenUsageDisplayMode: String, CaseIterable, Sendable, Identifiable {
    case remaining
    case used

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .remaining: return "Remaining"
        case .used: return "Used"
        }
    }
}

public enum TokenProviderKind: String, CaseIterable, Sendable, Identifiable {
    case claude
    case codex
    case openAI = "openai"
    case gemini
    case antigravity
    case copilot
    case cursor
    case grok
    case vertexAI = "vertexai"
    case bedrock

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .antigravity: return "Gemini (Agy)"
        case .copilot: return "GitHub Copilot"
        case .cursor: return "Cursor"
        case .grok: return "Grok"
        case .vertexAI: return "Vertex AI"
        case .bedrock: return "Bedrock"
        }
    }

    public var supportsCostSnapshot: Bool {
        switch self {
        case .claude, .codex, .vertexAI, .bedrock:
            return true
        case .openAI, .gemini, .antigravity, .copilot, .cursor, .grok:
            return false
        }
    }

    public var supportsQuotaSnapshot: Bool {
        switch self {
        case .antigravity, .copilot:
            return true
        case .claude, .codex, .openAI, .gemini, .cursor, .grok, .vertexAI, .bedrock:
            return false
        }
    }

    public var supportsLiveUsageSnapshot: Bool {
        switch self {
        case .claude, .codex, .gemini, .antigravity, .copilot, .cursor, .grok:
            return true
        case .openAI, .vertexAI, .bedrock:
            return false
        }
    }

    public var settingsBadge: String {
        if supportsCostSnapshot && supportsLiveUsageSnapshot { return "live + cost" }
        if supportsQuotaSnapshot { return "quota" }
        if supportsCostSnapshot { return "cost" }
        if supportsLiveUsageSnapshot { return "live" }
        return "pending"
    }

    public var capabilityLabels: [String] {
        var labels: [String] = []
        if supportsLiveUsageSnapshot { labels.append("Live") }
        if supportsCostSnapshot { labels.append("Cost") }
        if supportsQuotaSnapshot { labels.append("Quota") }
        if labels.isEmpty { labels.append("Pending") }
        return labels
    }

    public var capabilitySummary: String {
        capabilityLabels.joined(separator: " / ")
    }

    public var settingsDetail: String {
        switch self {
        case .antigravity:
            return "Gemini quota via Agy"
        case .copilot:
            return "Copilot premium request usage"
        case .claude, .codex:
            return "Local usage + cost snapshot"
        case .vertexAI, .bedrock:
            return "Cost snapshot"
        case .gemini, .cursor:
            return "Live usage adapter"
        case .grok:
            return "Grok credits via CLI/web billing"
        case .openAI:
            return "adapter pending"
        }
    }

    public var expectedDataText: String {
        switch self {
        case .claude:
            return "Local session tokens, 30d cost, optional live account metadata"
        case .codex:
            return "Local session tokens, 30d cost, optional CLI metadata"
        case .openAI:
            return "Pending direct usage adapter"
        case .gemini:
            return "Live usage route pending provider verification"
        case .antigravity:
            return "Gemini Models quota windows from Agy"
        case .copilot:
            return "Premium requests and Copilot quota from GitHub API"
        case .cursor:
            return "Live usage route pending provider verification"
        case .grok:
            return "Credits window from grok agent billing or grok.com session"
        case .vertexAI:
            return "Local / configured cost snapshot"
        case .bedrock:
            return "Local / configured cost snapshot"
        }
    }

    public static let defaultVisible: [TokenProviderKind] = [
        .codex,
        .copilot,
        .claude,
        .antigravity,
        .grok,
    ]
}

public enum ProviderUsageStatus: String, Sendable {
    case idle
    case refreshing
    case available
    case unsupported
    case unavailable

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .refreshing: return "Refreshing"
        case .available: return "Available"
        case .unsupported: return "Unsupported"
        case .unavailable: return "No data"
        }
    }

    public var isAttentionState: Bool {
        switch self {
        case .unsupported, .unavailable:
            return true
        case .idle, .refreshing, .available:
            return false
        }
    }
}

public enum ProviderUsageWindowKind: String, Sendable {
    case fiveHour
    case weekly
    case monthly
    case model
    case other

    public var displayName: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .model: return "Model"
        case .other: return "Quota"
        }
    }
}
