//
//  PollingDriver.swift — 共用的主執行緒輪詢驅動器
//

import Foundation

@MainActor
public final class PollingDriver {
    private var pollingTask: Task<Void, Never>?

    public init() {}

    /// 取消舊輪詢後啟動；立即執行一次 tick，之後每 interval（下限 1 秒）執行一次。
    public func start(interval: TimeInterval, tick: @escaping @MainActor () async -> Void) {
        stop()
        let seconds = max(1, interval)
        pollingTask = Task {
            await tick()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await tick()
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
