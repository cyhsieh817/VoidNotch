import Foundation

protocol AgentActivityChangeDetecting: Sendable {
    func prepareToFetchAgentActivity() async -> Bool
    func commitFetchedAgentActivity() async
}

actor AgentEventLogChangeDetector {
    struct Snapshot: Equatable, Sendable {
        let size: UInt64
        let modificationDate: Date
    }

    private let eventLogURL: URL
    private let fileManager: FileManager
    private var hasCommittedSnapshot = false
    private var committedSnapshot: Snapshot?
    private var pendingSnapshot: Snapshot?

    init(eventLogURL: URL, fileManager: FileManager = .default) {
        self.eventLogURL = eventLogURL
        self.fileManager = fileManager
    }

    func prepareToFetch() -> Bool {
        let snapshot = currentSnapshot()
        if hasCommittedSnapshot, snapshot == committedSnapshot {
            pendingSnapshot = nil
            return false
        }
        pendingSnapshot = snapshot
        return true
    }

    func commitFetched() {
        committedSnapshot = pendingSnapshot
        hasCommittedSnapshot = true
        pendingSnapshot = nil
    }

    private func currentSnapshot() -> Snapshot? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: eventLogURL.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modificationDate = attributes[.modificationDate] as? Date
        else { return nil }
        return Snapshot(size: size, modificationDate: modificationDate)
    }
}

public struct PeonPingAgentActivityProvider: AgentActivityProviding, AgentActivityChangeDetecting {
    public let eventLogURL: URL
    public let retentionSeconds: TimeInterval
    private let changeDetector: AgentEventLogChangeDetector

    public init(
        eventLogURL: URL = Self.defaultEventLogURL(),
        retentionSeconds: TimeInterval = 24 * 60 * 60)
    {
        self.eventLogURL = eventLogURL
        self.retentionSeconds = retentionSeconds
        self.changeDetector = AgentEventLogChangeDetector(eventLogURL: eventLogURL)
    }

    func prepareToFetchAgentActivity() async -> Bool {
        await changeDetector.prepareToFetch()
    }

    func commitFetchedAgentActivity() async {
        await changeDetector.commitFetched()
    }

    public func fetchEvents() async -> [AgentActivityEvent] {
        // 256KB tail 讀取移出呼叫端(MainActor)執行緒，避免每秒輪詢造成主執行緒微卡頓。
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
