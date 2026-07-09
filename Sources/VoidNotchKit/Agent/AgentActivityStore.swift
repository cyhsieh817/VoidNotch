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
    private var pollingTask: Task<Void, Never>?

    public init(activityProvider: any AgentActivityProviding = EmptyAgentActivityProvider()) {
        self.activityProvider = activityProvider
        self.events = []
    }

    public convenience init(events: [AgentActivityEvent]) {
        self.init(activityProvider: StaticAgentActivityProvider(events))
        self.events = Self.ordered(events)
        self.lastRefreshedAt = Date()
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

    public func refresh() async {
        isRefreshing = true
        let snapshots = await activityProvider.fetchEvents()
        events = Self.ordered(snapshots)
        lastRefreshedAt = Date()
        isRefreshing = false
    }

    public func startPolling(interval: TimeInterval = 15) {
        stopPolling()
        let seconds = max(5, interval)
        pollingTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await self?.refresh()
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private static func ordered(_ snapshots: [AgentActivityEvent]) -> [AgentActivityEvent] {
        Array(snapshots.sorted { $0.occurredAt > $1.occurredAt }.prefix(8))
    }
}
