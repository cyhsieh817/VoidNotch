import Foundation

/// 聲音節流閘：畫面提示不經過此閘，只有語音經過。
/// 去重鍵為狀態分類；一般狀態 10 秒窗口，needsInput/failed 穿透但帶 2 秒防連發地板。
public final class PeonSoundGate {
    private static let normalWindow: TimeInterval = 10
    private static let highPriorityFloor: TimeInterval = 2

    private var lastPlayedByStatus: [AgentActivityStatus: Date] = [:]

    public init() {}

    private func isHighPriority(_ status: AgentActivityStatus) -> Bool {
        status == .needsInput || status == .failed
    }

    /// 回傳是否該播放；有副作用（更新戳記）。at 由呼叫端傳入當前時刻。
    public func shouldPlay(status: AgentActivityStatus, at now: Date) -> Bool {
        let window = isHighPriority(status) ? Self.highPriorityFloor : Self.normalWindow
        if let last = lastPlayedByStatus[status], now.timeIntervalSince(last) < window {
            return false
        }
        lastPlayedByStatus[status] = now
        return true
    }
}
