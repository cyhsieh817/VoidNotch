//
//  HookWiringSettingsView.swift — 設定頁「Agent 提示接線」區塊
//
//  常駐顯示四個 agent（Claude/Codex/Grok/pi）的 hook 接線狀態，
//  可單獨「接線」；「解除」為後續增強（brief §10 YAGNI），本版僅回報 stub 訊息，不做破壞性操作。
//

import SwiftUI
import VoidNotchKit

/// 包住 HookInstaller 的輕量 view model：持有偵測到的狀態，並提供單一 agent 的「接線」動作。
@MainActor
@Observable
final class HookWiringStore {
    private let installer: HookInstaller
    private(set) var states: [AgentActivityProviderKind: HookStatus] = [:]

    init(installer: HookInstaller) {
        self.installer = installer
    }

    func refresh() {
        states = installer.detectAll(fs: RealFS())
    }

    /// 沿用偵測到的實際狀態（notInstalled 或 conflict）落地單一 agent，而非硬編 .notInstalled。
    @discardableResult
    func rewire(_ kind: AgentActivityProviderKind) -> [InstallResult] {
        if states.isEmpty { refresh() }
        guard let status = states[kind] else { return [] }
        let results = installer.installAll(states: [kind: status])
        refresh()
        return results
    }
}

struct HookWiringSettingsView: View {
    let l10n: L10n
    let states: [AgentActivityProviderKind: HookStatus]
    let onRewire: (AgentActivityProviderKind) -> Void
    let onUnwire: (AgentActivityProviderKind) -> Void

    private let allKinds: [AgentActivityProviderKind] = [.claude, .codex, .grok, .pi, .hermes]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.hookWiringTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            ForEach(allKinds) { kind in
                HStack(spacing: 10) {
                    Text(kind.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 90, alignment: .leading)
                    Text(statusText(states[kind]))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if states[kind] == .installed {
                        Button(l10n.hookUnwire) { onUnwire(kind) }
                    } else if states[kind] != .agentAbsent {
                        Button(l10n.hookWire) { onRewire(kind) }
                    }
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func statusText(_ status: HookStatus?) -> String {
        switch status {
        case .installed: return l10n.hookStatusInstalled
        case .notInstalled: return l10n.hookStatusNotInstalled
        case .agentAbsent: return l10n.hookStatusAgentAbsent
        case .conflict(let message): return l10n.hookStatusConflict(message)
        case .none: return "N/A"
        }
    }
}
