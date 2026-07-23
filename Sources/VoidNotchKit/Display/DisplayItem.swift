import Foundation

/// menubar 與 gauge 共用的統一顯示項目目錄。系統指標 + AI 用量 + agent 活躍。
public enum DisplayItem: Hashable, Sendable {
    case system(SystemMetricKind)
    case aiUsage
    case agentActivity

    /// 持久化 / 選單 identity 用的穩定字串鍵。
    public var storageKey: String {
        switch self {
        case .system(let kind): return "system.\(kind.rawValue)"
        case .aiUsage: return "aiUsage"
        case .agentActivity: return "agentActivity"
        }
    }

    public init?(storageKey: String) {
        switch storageKey {
        case "aiUsage": self = .aiUsage
        case "agentActivity": self = .agentActivity
        default:
            let prefix = "system."
            guard storageKey.hasPrefix(prefix) else { return nil }
            let raw = String(storageKey.dropFirst(prefix.count))
            guard let kind = SystemMetricKind(rawValue: raw) else { return nil }
            self = .system(kind)
        }
    }

    /// 目錄順序：10 系統指標（settingsOrder）+ AI + agent。
    public static let catalog: [DisplayItem] =
        SystemMetricKind.settingsOrder.map(DisplayItem.system) + [.aiUsage, .agentActivity]

    public func label(language: AppLanguage) -> String {
        switch self {
        case .system(let kind): return kind.label(language: language)
        case .aiUsage: return language == .zhTW ? "AI 用量" : "AI"
        case .agentActivity: return language == .zhTW ? "Agent" : "Agent"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .system(let kind): return kind.iconSystemName
        case .aiUsage: return "brain.head.profile"
        case .agentActivity: return "dot.radiowaves.left.and.right"
        }
    }
}

/// 顏色語意鍵；View 層映射到 Theme.Colors，資料層不碰 SwiftUI Color。
public enum DisplayTint: Sendable {
    case cpu, mem, disk, network, battery, thermal, health, gpu, ai, agent, neutral, warning
}

/// agent 活躍摘要，供 reading 取數（避免 VoidNotchKit 反依賴 App store）。
public struct AgentActivitySummary: Sendable, Equatable {
    public var activeCount: Int
    public var attentionCount: Int
    public init(activeCount: Int, attentionCount: Int) {
        self.activeCount = activeCount
        self.attentionCount = attentionCount
    }
}
