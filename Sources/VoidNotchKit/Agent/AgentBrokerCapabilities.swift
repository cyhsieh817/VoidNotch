import Foundation

/// App 啟動時宣告：這一版能不能在瀏海直接回答 agent 的提問。
///
/// 為什麼需要這層握手：relay 一旦決定接管某個提問，就會擋住 agent 去等回應檔。
/// 這個版本一律回報「不可代答」（`answerable_providers` 固定空陣列），
/// relay 看到空清單就不會把問答讓渡給瀏海，agent 一律照舊回終端機等答案。
/// 保留這個檔案本身（relay 仍會讀它探知 App 有沒有裝、版本新不新），
/// 只是內容不再宣告任何可代答的 provider。
public enum AgentBrokerCapabilities {
    public static let schemaVersion = 1

    public static func fileURL(support: URL) -> URL {
        support.appendingPathComponent("VoidNotch/broker-capabilities.json")
    }

    /// 冪等；失敗只代表 relay 會退回保守模式，不該讓 App 啟動失敗。
    @discardableResult
    public static func announce() -> Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return announce(support: support)
    }

    @discardableResult
    static func announce(support: URL) -> Bool {
        do {
            let destination = fileURL(support: support)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let payload: [String: Any] = [
                "schema_version": schemaVersion,
                "answerable_providers": [String](),
            ]
            try JSONSerialization.data(withJSONObject: payload).write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
