//
//  AgentActivityStore.swift — @Observable store for agent activity events
//
//  Moved from App/Monitors/AgentActivityStore.swift into VoidNotchKit.
//

import Foundation
import Observation

@Observable
@MainActor
public final class AgentActivityStore {
    public private(set) var events: [AgentActivityEvent]
    public private(set) var isRefreshing = false
    public private(set) var lastRefreshedAt: Date?

    private let activityProvider: any AgentActivityProviding
    private let pollingDriver = PollingDriver()
    private var isPreparingRefresh = false
    private var seenEventIDs: Set<UUID>?
    private var seenInputRequestIDs = Set<UUID>()
    private var onNewEvent: (@MainActor (AgentActivityEvent) -> Void)?

    public init(activityProvider: any AgentActivityProviding = EmptyAgentActivityProvider()) {
        self.activityProvider = activityProvider
        self.events = []
    }

    public convenience init(events: [AgentActivityEvent], now: Date = Date()) {
        self.init(activityProvider: StaticAgentActivityProvider(events))
        self.events = Self.displayEvents(from: events, now: now)
        self.lastRefreshedAt = now
    }

    public var currentEvent: AgentActivityEvent? {
        events.first
    }

    public var activeEventCount: Int {
        events.filter { $0.status.isActiveState }.count
    }

    public var attentionEventCount: Int {
        events.filter { $0.status.isAttentionState }.count
    }

    public var recentEventCount: Int {
        events.count
    }

    public var compactText: String {
        currentEvent?.compactText ?? "Agents idle"
    }

    public func refresh(now: Date = Date()) async {
        guard !isRefreshing, !isPreparingRefresh else { return }
        let changeDetector = activityProvider as? any AgentActivityChangeDetecting
        if let changeDetector {
            isPreparingRefresh = true
            let shouldRefresh = await changeDetector.prepareToFetchAgentActivity()
            isPreparingRefresh = false
            guard shouldRefresh else {
                let displayedEvents = Self.displayEvents(from: events, now: now)
                if displayedEvents != events {
                    events = displayedEvents
                }
                lastRefreshedAt = now
                return
            }
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        let snapshots = await activityProvider.fetchEvents()
        await changeDetector?.commitFetchedAgentActivity()
        dispatchNewEvents(from: snapshots)
        let orderedSnapshots = Self.displayEvents(from: snapshots, now: now)
        if orderedSnapshots != events {
            events = orderedSnapshots
        }
        lastRefreshedAt = now
        isRefreshing = false
    }

    public func startPolling(
        interval: TimeInterval = 15,
        onNewEvent: (@MainActor (AgentActivityEvent) -> Void)? = nil)
    {
        stopPolling()
        self.onNewEvent = onNewEvent
        seenEventIDs = nil
        seenInputRequestIDs = []
        pollingDriver.start(interval: interval) { [weak self] in
            await self?.refresh()
        }
    }

    public func stopPolling() {
        pollingDriver.stop()
    }

    private func dispatchNewEvents(from snapshots: [AgentActivityEvent]) {
        let snapshotIDs = Set(snapshots.map(\.id))
        guard let previousIDs = seenEventIDs else {
            // 一般歷史事件只建立基線；最近 300 秒內的待答卡要回放，避免啟動時卡片競態消失。
            seenEventIDs = snapshotIDs
            seenInputRequestIDs = Set(snapshots.compactMap { $0.inputRequest?.requestID })
            let cutoff = Date().addingTimeInterval(-Self.inputRequestReplayWindow)
            var replayedRequestIDs = Set<UUID>()
            let freshInputRequests = snapshots
                .filter { event in
                    event.inputRequest != nil && event.occurredAt >= cutoff
                }
                .sorted { $0.occurredAt < $1.occurredAt }
            for event in freshInputRequests {
                guard let requestID = event.inputRequest?.requestID,
                      replayedRequestIDs.insert(requestID).inserted
                else { continue }
                onNewEvent?(event)
            }
            return
        }

        // 先判定新事件，再以當前快照覆寫 seen 集合（避免無界累積，且不誤判仍在窗內者）。
        let newEvents = snapshots
            .filter { event in
                guard !previousIDs.contains(event.id), Self.shouldNotify(for: event.status) else {
                    return false
                }
                guard let requestID = event.inputRequest?.requestID else { return true }
                return seenInputRequestIDs.insert(requestID).inserted
            }
            .sorted { $0.occurredAt < $1.occurredAt }
        seenEventIDs = snapshotIDs
        for event in newEvents {
            onNewEvent?(event)
        }
    }

    private static func shouldNotify(for status: AgentActivityStatus) -> Bool {
        switch status {
        case .started, .completed, .needsInput, .failed, .resourceLimit:
            return true
        case .running, .stopped:
            return false
        }
    }

    public static let inputRequestReplayWindow: TimeInterval = 300
    public static let activityDisplayWindow: TimeInterval = 30
    public static let activityFutureSkewAllowance: TimeInterval = 5
    public static let activityDisplayMaximumCount = 50

    /// 將完整 snapshot 投影成 UI 顯示資料；呼叫端的 dispatch/dedupe 不得使用這個投影。
    public static func displayEvents(
        from snapshots: [AgentActivityEvent],
        now: Date = Date()) -> [AgentActivityEvent]
    {
        let lowerBound = now.addingTimeInterval(-activityDisplayWindow)
        let upperBound = now.addingTimeInterval(activityFutureSkewAllowance)
        let newestFirst = snapshots.sorted { $0.occurredAt > $1.occurredAt }
        let recent = newestFirst.filter {
            $0.occurredAt >= lowerBound && $0.occurredAt <= upperBound
        }

        return Array(recent.prefix(activityDisplayMaximumCount))
    }
}
