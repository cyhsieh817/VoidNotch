import Foundation

/// 這一家 agent 的提問，能不能在瀏海直接作答。
///
/// 「有 hook」不等於「能代答」——多數 agent 的 hook 協定只能通知、擋，不能回填答案。
/// 介面必須把這件事講明白，否則使用者會以為 hermes 壞了（其實是它的協定就做不到）。
public enum AgentAnswerCapability: Sendable {
    /// 可在瀏海直接作答（提問／核准）
    case answerable
    /// 只能顯示活動，作答仍須回終端機
    case notifyOnly

    public func label(_ l10n: L10n) -> String {
        switch self {
        case .answerable: return l10n.capabilityAnswerable
        case .notifyOnly: return l10n.capabilityNotifyOnly
        }
    }
}

/// 單一 agent 的接通狀態＋能力，供瀏海的診斷區塊顯示。
public struct AgentConnectionState: Identifiable, Sendable {
    public let provider: AgentActivityProviderKind
    public let hook: HookStatus
    public let capability: AgentAnswerCapability

    public var id: String { provider.rawValue }

    public init(provider: AgentActivityProviderKind, hook: HookStatus, capability: AgentAnswerCapability) {
        self.provider = provider
        self.hook = hook
        self.capability = capability
    }

    /// hook 真的會觸發嗎。`.conflict` 不算——設定在、卻不會跑（例如 hermes 沒進 allowlist）。
    public var isWired: Bool { hook == .installed }

    /// 這家 agent 沒裝，本來就不該報問題。
    public var isAbsent: Bool { hook == .agentAbsent }

    /// 一句話說明現況；沒接通時直接給出下一步，而不是只說「未接通」。
    public func detail(_ l10n: L10n) -> String {
        switch hook {
        case .installed:
            return capability == .answerable
                ? l10n.connectionDetailInstalledAnswerable : l10n.connectionDetailInstalledNotifyOnly
        case .notInstalled:
            return l10n.connectionDetailNotInstalled
        case .agentAbsent:
            return l10n.connectionDetailAgentAbsent
        case .conflict(let reason):
            return l10n.connectionDetailConflict(reason)
        }
    }
}

public enum AgentConnectionDiagnostics {
    /// 能力的單一真相源＝ App 對 relay 的宣告（broker-capabilities.json）。
    /// 分開維護兩份清單，遲早會出現「介面說可作答、relay 卻不接管」的鬼打牆。
    public static func capability(for provider: AgentActivityProviderKind) -> AgentAnswerCapability {
        AgentBrokerCapabilities.answerableProviders.contains(provider.rawValue) ? .answerable : .notifyOnly
    }

    /// 把 HookInstaller.detectAll 的結果整理成可顯示的清單。
    /// 未安裝的 agent 不列出——沒裝 codex 的人不需要看到一排紅字。
    public static func states(
        from statuses: [AgentActivityProviderKind: HookStatus]
    ) -> [AgentConnectionState] {
        AgentActivityProviderKind.allCases.compactMap { provider in
            guard let hook = statuses[provider] else { return nil }
            let state = AgentConnectionState(
                provider: provider, hook: hook, capability: capability(for: provider)
            )
            return state.isAbsent ? nil : state
        }
    }

    /// 需要使用者處理的家數（未接通或有衝突）。給 badge 用。
    public static func attentionCount(_ states: [AgentConnectionState]) -> Int {
        states.filter { !$0.isWired }.count
    }
}
