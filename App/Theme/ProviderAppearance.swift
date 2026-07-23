//
//  ProviderAppearance.swift — provider / 狀態的視覺對應（單一真相）
//
//  TokenWidget 與 ProviderSettingsView 先前各持一份逐字相同的 switch；
//  集中於此，新增 provider 只需改這裡與 VoidNotchKit 的 TokenProviderKind。
//

import SwiftUI
import VoidNotchKit

enum ProviderIconChoice: String, CaseIterable, Identifiable {
    case `default`
    case systemHealth
    case modelUsage
    case agentActivity
    case notification
    case displayMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return "Default"
        case .systemHealth: return "System Health"
        case .modelUsage: return "Model Usage"
        case .agentActivity: return "Agent Activity"
        case .notification: return "Notification"
        case .displayMode: return "Display Mode"
        }
    }

    var resourceName: String? {
        switch self {
        case .default: return nil
        case .systemHealth: return "system-health"
        case .modelUsage: return "model-usage"
        case .agentActivity: return "agent-activity"
        case .notification: return "notification"
        case .displayMode: return "display-mode"
        }
    }

    static func preferenceKey(for provider: TokenProviderKind) -> String {
        "VoidNotch.providerIcon.\(provider.rawValue)"
    }
}

extension TokenProviderKind {
    var iconSystemName: String {
        switch self {
        case .claude: return "cpu"
        case .codex: return "terminal"
        case .openAI: return "circle.hexagongrid"
        case .gemini: return "sparkles"
        case .antigravity: return "atom"
        case .copilot: return "curlybraces.square"
        case .cursor: return "cursorarrow.click"
        case .grok: return "bolt.horizontal.fill"
        case .vertexAI: return "triangle.3"
        case .bedrock: return "server.rack"
        }
    }

    var tint: Color {
        switch self {
        case .claude: return .cyan
        case .codex: return .blue
        case .openAI: return .mint
        case .gemini: return .green
        case .antigravity: return .purple
        case .copilot: return .indigo
        case .cursor: return .white
        // CodexBar Grok teal: rgb(16, 163, 127)
        case .grok: return Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255)
        case .vertexAI: return .orange
        case .bedrock: return .yellow
        }
    }

    var compactName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .antigravity: return "Agy"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        case .grok: return "Grok"
        case .vertexAI: return "Vertex"
        case .bedrock: return "Bedrock"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .antigravity: return "Agy"
        case .copilot: return "Copilot"
        case .grok: return "Grok"
        case .vertexAI: return "Vertex"
        default: return displayName
        }
    }
}

extension ProviderUsageStatus {
    var statusColor: Color {
        switch self {
        case .available: return .green
        case .refreshing: return .blue
        case .unsupported: return .orange
        case .unavailable: return .red
        case .idle: return .secondary
        }
    }

    var dotColor: Color { statusColor }

    var borderColor: Color {
        switch self {
        case .available, .idle:
            return .white.opacity(0.08)
        case .refreshing:
            return .blue.opacity(0.22)
        case .unsupported:
            return .orange.opacity(0.28)
        case .unavailable:
            return .red.opacity(0.25)
        }
    }
}
