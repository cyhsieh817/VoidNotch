import Foundation

/// App 啟動時宣告：這一版**真的答得出來**哪些 provider 的請求。
///
/// 為什麼需要這層握手：relay 一旦決定接管某個提問，就會擋住 agent 去等回應檔。
/// 若 App 根本不認得那個 provider 的卡片（例如舊版只認 claude），它既不會顯示可按的選項、
/// 也不會寫回 dismissal，relay 就會一路空等到 broker timeout——agent 反而比沒裝 VoidNotch 還慢。
/// 版本錯配是常態（relay 裝在使用者家目錄，App 各自更新），所以必須讓 relay 問得到「你答得了嗎」。
public enum AgentBrokerCapabilities {
    public static let schemaVersion = 1

    /// 能在瀏海直接作答的 provider。新增可作答的 provider 時，這裡與 relay 都要跟著加。
    public static let answerableProviders = ["claude", "codex", "pi"]

    public static func fileURL(support: URL) -> URL {
        support.appendingPathComponent("VoidNotch/broker-capabilities.json")
    }

    /// 冪等；失敗只代表 relay 會退回保守模式，不該讓 App 啟動失敗。
    @discardableResult
    public static func announce(isPro: Bool) -> Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return announce(isPro: isPro, support: support)
    }

    @discardableResult
    static func announce(isPro: Bool, support: URL) -> Bool {
        do {
            let destination = fileURL(support: support)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let payload: [String: Any] = [
                "schema_version": schemaVersion,
                "answerable_providers": isPro ? answerableProviders : [],
            ]
            try JSONSerialization.data(withJSONObject: payload).write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
