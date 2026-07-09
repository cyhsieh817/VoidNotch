//
//  AgentActivityStore.swift — App-layer provider only
//
//  Models / store / parser have been moved to VoidNotchKit.
//  This file now contains only PeonPingAgentActivityProvider,
//  which handles file IO and delegates parsing to AgentEventLogParser.
//

import Foundation
import VoidNotchKit

public struct PeonPingAgentActivityProvider: AgentActivityProviding {
    public let eventLogURL: URL
    public let retentionSeconds: TimeInterval

    public init(
        eventLogURL: URL = Self.defaultEventLogURL(),
        retentionSeconds: TimeInterval = 24 * 60 * 60)
    {
        self.eventLogURL = eventLogURL
        self.retentionSeconds = retentionSeconds
    }

    public func fetchEvents() async -> [AgentActivityEvent] {
        // 256KB 檔案讀取移出呼叫端(MainActor)執行緒,避免常駐每 15 秒的主執行緒微卡頓。
        let url = eventLogURL
        let retention = retentionSeconds
        return await Task.detached(priority: .utility) {
            AgentEventLogReader.loadEvents(
                from: url,
                maxReadBytes: AgentEventLogReader.defaultMaxReadBytes,
                retentionSeconds: retention,
                createDirectoryIfMissing: true)
        }.value
    }

    public static func defaultEventLogURL() -> URL {
        // (原樣保留:VOIDNOTCH_AGENT_EVENTS 覆寫 → Application Support/VoidNotch/agent-events.jsonl)
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["VOIDNOTCH_AGENT_EVENTS"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("VoidNotch", isDirectory: true)
            .appendingPathComponent("agent-events.jsonl")
    }

}
