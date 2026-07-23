import Foundation

/// hermes（NousResearch/hermes-agent）的 shell hooks。**只通知，不代答**：
/// 其 hook 回傳協定僅認 block / context，沒有 updatedInput 等價物，回不了答案。
///
/// 這個 adapter 只做偵測，不做安裝：hermes 的設定是 YAML（手工維護、滿是註解），
/// 用程式重寫會把註解沖掉；且還要一併寫 allowlist。一鍵接通留待日後補上。
public struct HermesHookAdapter: AgentHookAdapter {
    public let kind: AgentActivityProviderKind = .hermes
    private let fs: FileSystemReading

    /// config.yaml 與 allowlist 都要含這段，才算真的接通。
    static let relayMarker = "--provider hermes"

    public init(fs: FileSystemReading) { self.fs = fs }

    public func detect(fs: FileSystemReading, paths: HookPaths) -> HookStatus {
        guard fs.fileExists(paths.home.appendingPathComponent(".hermes")) else { return .agentAbsent }

        guard let configData = fs.readData(paths.hermesConfig),
              let config = String(data: configData, encoding: .utf8)
        else { return .notInstalled }

        guard config.contains(Self.relayMarker) else { return .notInstalled }

        // 設定掛了不代表會跑：hooks_auto_accept: false 時，未進 allowlist 的 hook 會被
        // 靜默略過（`hermes hooks list` 顯示 not allowlisted）。這是最容易誤判成「已接通」
        // 的半死狀態，必須單獨報出來。
        guard let allowData = fs.readData(paths.hermesAllowlist),
              let allow = String(data: allowData, encoding: .utf8),
              allow.contains(Self.relayMarker)
        else {
            return .conflict("hooks 已設定但未列入 allowlist，不會觸發（跑 hermes hooks doctor）")
        }

        return .installed
    }

    /// hermes 無法一鍵接通——需手動編輯 YAML 與 allowlist。誠實報錯，不要用空 plan 假裝成功。
    public func plan(paths: HookPaths) throws -> [HookMutation] {
        throw HookPlanError.malformed(
            "hermes 需手動設定：在 ~/.hermes/config.yaml 加 hooks: 區塊，"
            + "並用 hermes hooks doctor 確認已列入 allowlist"
        )
    }
}
