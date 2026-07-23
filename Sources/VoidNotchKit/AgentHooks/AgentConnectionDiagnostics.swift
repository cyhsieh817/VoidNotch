import Foundation

/// 單一 agent 的接通狀態，供瀏海的診斷區塊顯示。
public struct AgentConnectionState: Identifiable, Sendable {
    public let provider: AgentActivityProviderKind
    public let hook: HookStatus

    public var id: String { provider.rawValue }

    public init(provider: AgentActivityProviderKind, hook: HookStatus) {
        self.provider = provider
        self.hook = hook
    }

    /// hook 真的會觸發嗎。`.conflict` 不算——設定在、卻不會跑（例如 hermes 沒進 allowlist）。
    public var isWired: Bool { hook == .installed }

    /// 這家 agent 沒裝，本來就不該報問題。
    public var isAbsent: Bool { hook == .agentAbsent }

    /// 一句話說明現況；沒接通時直接給出下一步，而不是只說「未接通」。
    public func detail(_ l10n: L10n) -> String {
        switch hook {
        case .installed:
            return l10n.connectionDetailInstalled
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
    /// 把 HookInstaller.detectAll 的結果整理成可顯示的清單。
    /// 未安裝的 agent 不列出——沒裝 codex 的人不需要看到一排紅字。
    public static func states(
        from statuses: [AgentActivityProviderKind: HookStatus]
    ) -> [AgentConnectionState] {
        AgentActivityProviderKind.allCases.compactMap { provider in
            guard let hook = statuses[provider] else { return nil }
            let state = AgentConnectionState(provider: provider, hook: hook)
            return state.isAbsent ? nil : state
        }
    }

    /// 需要使用者處理的家數（未接通或有衝突）。給 badge 用。
    public static func attentionCount(_ states: [AgentConnectionState]) -> Int {
        states.filter { !$0.isWired }.count
    }
}
