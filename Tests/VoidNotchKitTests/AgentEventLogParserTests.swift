import os
import XCTest
@testable import VoidNotchKit

final class AgentEventLogParserTests: XCTestCase {
    func test_parses_complete_input_request() {
        let line = #"{"provider":"claude","status":"needsInput","input_request":{"request_id":"123E4567-E89B-12D3-A456-426614174000","questions":[{"question":"Choose","header":"Mode","multiSelect":false,"options":[{"label":"A","description":"First"}]}]}}"#
        let request = AgentEventLogParser.parseEventLine(line)?.inputRequest
        XCTAssertEqual(request?.requestID.uuidString, "123E4567-E89B-12D3-A456-426614174000")
        XCTAssertEqual(request?.questions.first?.question, "Choose")
        XCTAssertEqual(request?.questions.first?.header, "Mode")
        XCTAssertEqual(request?.questions.first?.multiSelect, false)
        XCTAssertEqual(request?.questions.first?.options.first?.label, "A")
        XCTAssertEqual(request?.questions.first?.options.first?.description, "First")
    }

    // pi 的 extension 直接寫 JSONL（不經 relay），request_id 是小寫。
    // isAnswerable 只是「有沒有 inputRequest」的觀測旗標，不是 provider 是不是 claude；
    // VoidNotch 本身不再代答，這裡純粹驗證解析層有沒有正確帶出 inputRequest。
    func test_pi_input_request_carries_input_request() {
        let line = #"{"provider":"pi","status":"needsInput","input_request":{"request_id":"3b0bc78d-9846-4ca2-8289-9646d2319f39","questions":[{"question":"選一個","header":"決策","multiSelect":false,"options":[{"label":"甲","description":""}]}]}}"#
        let event = AgentEventLogParser.parseEventLine(line)
        XCTAssertEqual(event?.provider, .pi)
        XCTAssertEqual(event?.isAnswerable, true)
        XCTAssertEqual(event?.inputRequest?.questions.first?.options.first?.label, "甲")
    }

    func test_event_without_input_request_has_no_input_request() {
        let line = #"{"provider":"pi","status":"completed"}"#
        XCTAssertEqual(AgentEventLogParser.parseEventLine(line)?.isAnswerable, false)
    }

    func test_rejects_incomplete_input_request_without_dropping_event() {
        let line = #"{"provider":"claude","status":"needsInput","input_request":{"request_id":"123E4567-E89B-12D3-A456-426614174000","questions":[]}}"#
        XCTAssertNil(AgentEventLogParser.parseEventLine(line)?.inputRequest)
    }

    func test_rejects_question_without_options_without_dropping_event() {
        let line = #"{"provider":"claude","status":"needsInput","input_request":{"request_id":"123E4567-E89B-12D3-A456-426614174000","questions":[{"question":"Choose","header":"Mode","multiSelect":false,"options":[]}]}}"#
        let event = AgentEventLogParser.parseEventLine(line)
        XCTAssertEqual(event?.status, .needsInput)
        XCTAssertNil(event?.inputRequest)
    }

    func test_rejects_duplicate_option_labels_without_dropping_needsInput_event() {
        let line = #"{"provider":"claude","status":"needsInput","input_request":{"request_id":"123E4567-E89B-12D3-A456-426614174000","questions":[{"question":"Choose","header":"Mode","multiSelect":false,"options":[{"label":"Yes","description":"A"},{"label":" yes ","description":"B"}]}]}}"#
        let event = AgentEventLogParser.parseEventLine(line)
        XCTAssertEqual(event?.status, .needsInput)
        XCTAssertNil(event?.inputRequest)
    }

    func test_plain_needs_input_has_no_request() {
        XCTAssertNil(AgentEventLogParser.parseEventLine(#"{"provider":"codex","status":"needsInput"}"#)?.inputRequest)
    }
    func test_parses_valid_jsonl_line() {
        let line = #"{"provider":"claude","status":"running","title":"Build","cwd":"/Users/x/Repo"}"#
        let event = AgentEventLogParser.parseEventLine(line)
        XCTAssertEqual(event?.provider, .claude)
        XCTAssertEqual(event?.status, .running)
        XCTAssertEqual(event?.title, "Build")
        XCTAssertEqual(event?.workspace, "Repo")
    }

    func test_parses_valid_navigation_target() {
        let line = #"{"provider":"claude","status":"completed","title":"Build","navigation":{"source_surface":"ghostty","session_id":"sess-1","tmux_socket":"/private/tmp/tmux.sock","tmux_pane":"%12","tmux_window":"@3","tmux_session":"work","tmux_client_tty":"/dev/ttys001"}}"#
        let navigation = AgentEventLogParser.parseEventLine(line)?.navigation

        XCTAssertEqual(navigation?.sourceSurface, .ghostty)
        XCTAssertEqual(navigation?.sessionID, "sess-1")
        XCTAssertEqual(navigation?.tmuxSocket, "/private/tmp/tmux.sock")
        XCTAssertEqual(navigation?.tmuxPane, "%12")
        XCTAssertEqual(navigation?.tmuxWindow, "@3")
        XCTAssertEqual(navigation?.tmuxSession, "work")
        XCTAssertEqual(navigation?.tmuxClientTTY, "/dev/ttys001")
    }

    func test_invalid_navigation_values_degrade_without_dropping_event() {
        let line = #"{"provider":"codex","status":"completed","navigation":{"source_surface":"not-a-surface","session_id":" ","tmux_socket":"relative.sock","tmux_pane":"pane-1","tmux_window":"@x","tmux_session":"","tmux_client_tty":"/dev/null"}}"#
        let event = AgentEventLogParser.parseEventLine(line)

        XCTAssertEqual(event?.status, .completed)
        XCTAssertEqual(event?.navigation?.sourceSurface, .unknown)
        XCTAssertNil(event?.navigation?.sessionID)
        XCTAssertNil(event?.navigation?.tmuxSocket)
        XCTAssertNil(event?.navigation?.tmuxPane)
        XCTAssertNil(event?.navigation?.tmuxWindow)
        XCTAssertNil(event?.navigation?.tmuxSession)
        XCTAssertNil(event?.navigation?.tmuxClientTTY)
    }

    func test_legacy_event_without_navigation_remains_without_target() {
        let event = AgentEventLogParser.parseEventLine(#"{"provider":"claude","status":"running","title":"Legacy"}"#)

        XCTAssertNotNil(event)
        XCTAssertNil(event?.navigation)
    }

    func test_malformed_or_empty_returns_nil() {
        XCTAssertNil(AgentEventLogParser.parseEventLine("{not json"))
        XCTAssertNil(AgentEventLogParser.parseEventLine(""))
    }

    func test_unknown_provider_or_status_returns_nil() {
        XCTAssertNil(AgentEventLogParser.parseEventLine(#"{"provider":"unknown","status":"running"}"#))
        XCTAssertNil(AgentEventLogParser.parseEventLine(#"{"provider":"claude","status":"floop"}"#))
    }

    func test_hook_event_name_maps_to_status() {
        let event = AgentEventLogParser.parseEventLine(#"{"agent":"codex","hook_event_name":"UserPromptSubmit"}"#)
        XCTAssertEqual(event?.provider, .codex)
        XCTAssertEqual(event?.status, .running)
    }

    func test_retention_filters_old_events() {
        let now = Date(timeIntervalSince1970: 10_000)
        let old = #"{"provider":"claude","status":"running","ts":1000}"#
        let fresh = #"{"provider":"claude","status":"running","ts":9999}"#
        let events = AgentEventLogParser.parse(text: "\(old)\n\(fresh)",
                                               retentionCutoff: now.addingTimeInterval(-3600))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.occurredAt, Date(timeIntervalSince1970: 9999))
    }

    // MARK: - Provider grok/pi resolution (fixes #T9b silent drop bug)

    func test_provider_grok_resolves_via_contains() {
        let line = #"{"provider":"grok","status":"started"}"#
        let event = AgentEventLogParser.parseEventLine(line)
        XCTAssertNotNil(event, "grok provider should resolve")
        XCTAssertEqual(event?.provider, .grok)
        XCTAssertEqual(event?.status, .started)
    }

    func test_provider_pi_resolves_via_exact_match() {
        let line = #"{"provider":"pi","status":"started"}"#
        let event = AgentEventLogParser.parseEventLine(line)
        XCTAssertNotNil(event, "pi provider should resolve")
        XCTAssertEqual(event?.provider, .pi)
        XCTAssertEqual(event?.status, .started)
    }

    func test_provider_copilot_does_not_resolve_to_pi() {
        let line = #"{"provider":"copilot","status":"running"}"#
        let event = AgentEventLogParser.parseEventLine(line)
        XCTAssertNil(event, "copilot (contains 'pi') must NOT resolve to .pi via substring match")
    }
}

@MainActor
final class AgentActivityStoreDisplayWindowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeEvent(id: UUID = UUID(), occurredAt: Date) -> AgentActivityEvent {
        AgentActivityEvent(
            id: id,
            provider: .claude,
            status: .completed,
            title: id.uuidString,
            occurredAt: occurredAt)
    }

    func test_display_window_includes_thirty_seconds_and_five_second_future_skew() {
        let lowerBoundary = makeEvent(occurredAt: now.addingTimeInterval(-30))
        let upperBoundary = makeEvent(occurredAt: now.addingTimeInterval(5))
        let tooOld = makeEvent(occurredAt: now.addingTimeInterval(-30.1))
        let tooFuture = makeEvent(occurredAt: now.addingTimeInterval(5.1))
        let otherRecent = (0..<6).map { index in
            makeEvent(occurredAt: now.addingTimeInterval(-Double(index + 1)))
        }

        let displayed = AgentActivityStore.displayEvents(
            from: [tooOld, tooFuture, lowerBoundary, upperBoundary] + otherRecent,
            now: now)

        XCTAssertEqual(displayed.count, 8)
        XCTAssertTrue(displayed.contains(where: { $0.id == lowerBoundary.id }))
        XCTAssertTrue(displayed.contains(where: { $0.id == upperBoundary.id }))
        XCTAssertFalse(displayed.contains(where: { $0.id == tooOld.id }))
        XCTAssertFalse(displayed.contains(where: { $0.id == tooFuture.id }))
        XCTAssertEqual(displayed, displayed.sorted { $0.occurredAt > $1.occurredAt })
    }

    func test_display_window_hard_caps_at_fifty_recent_events() {
        let events = (0..<60).map { index in
            makeEvent(occurredAt: now.addingTimeInterval(-Double(index) / 2))
        }

        let displayed = AgentActivityStore.displayEvents(from: events, now: now)

        XCTAssertEqual(displayed.count, 50)
        XCTAssertEqual(displayed.first?.occurredAt, events.first?.occurredAt)
        XCTAssertEqual(displayed.last?.occurredAt, events[49].occurredAt)
    }

    func test_display_window_does_not_backfill_events_older_than_thirty_seconds() {
        let recent = (0..<3).map { index in
            makeEvent(occurredAt: now.addingTimeInterval(-Double(index + 1)))
        }
        let older = (0..<10).map { index in
            makeEvent(occurredAt: now.addingTimeInterval(-30.1 - Double(index)))
        }

        let displayed = AgentActivityStore.displayEvents(from: older + recent, now: now)

        XCTAssertEqual(displayed.count, 3)
        XCTAssertEqual(displayed.map(\.id), recent.map(\.id))
        XCTAssertFalse(displayed.contains(where: { older.contains($0) }))
    }

    func test_future_event_beyond_skew_is_not_used_as_activity_display() {
        let future = makeEvent(occurredAt: now.addingTimeInterval(6))

        XCTAssertTrue(AgentActivityStore.displayEvents(from: [future], now: now).isEmpty)
    }
}

/// 模擬檔案 snapshot 未變：首次 refresh 可 fetch，後續 refresh 由 change detector 擋下 fetch。
private actor UnchangedSnapshotAgentActivityProvider: AgentActivityProviding, AgentActivityChangeDetecting {
    private let snapshot: [AgentActivityEvent]
    private(set) var fetchCount = 0
    private var hasCommittedSnapshot = false

    init(snapshot: [AgentActivityEvent]) {
        self.snapshot = snapshot
    }

    func prepareToFetchAgentActivity() async -> Bool {
        !hasCommittedSnapshot
    }

    func commitFetchedAgentActivity() async {
        hasCommittedSnapshot = true
    }

    func fetchEvents() async -> [AgentActivityEvent] {
        fetchCount += 1
        return snapshot
    }
}

@MainActor
extension AgentActivityStoreDisplayWindowTests {
    func test_unchanged_snapshot_refresh_reapplies_time_window_without_fetching() async {
        let event = makeEvent(occurredAt: now.addingTimeInterval(-29.9))
        let provider = UnchangedSnapshotAgentActivityProvider(snapshot: [event])
        let store = AgentActivityStore(activityProvider: provider)

        await store.refresh(now: now)
        XCTAssertEqual(store.events.map(\.id), [event.id])

        let advancedNow = now.addingTimeInterval(0.2)
        await store.refresh(now: advancedNow)

        XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(store.lastRefreshedAt, advancedNow)
        let fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 1)
    }
}

// MARK: - AgentActivityStore new-event notification semantics (TDD; production API pending)

/// 依 `fetchEvents()` 呼叫次序回傳不同 snapshot；耗盡後重複最後一筆，避免 timer/sleep。
private final class SequencedAgentActivityProvider: AgentActivityProviding, @unchecked Sendable {
    private let snapshots: [[AgentActivityEvent]]
    private let callIndex = OSAllocatedUnfairLock(initialState: 0)

    init(snapshots: [[AgentActivityEvent]]) {
        precondition(!snapshots.isEmpty, "sequenced provider needs at least one snapshot")
        self.snapshots = snapshots
    }

    func fetchEvents() async -> [AgentActivityEvent] {
        let index = callIndex.withLock { state -> Int in
            let current = min(state, snapshots.count - 1)
            state += 1
            return current
        }
        return snapshots[index]
    }
}

@MainActor
private final class NewEventCollector {
    private(set) var events: [AgentActivityEvent] = []

    func append(_ event: AgentActivityEvent) {
        events.append(event)
    }

    var ids: [UUID] { events.map(\.id) }
    var statuses: [AgentActivityStatus] { events.map(\.status) }
}

/// 鎖定 `AgentActivityStore.startPolling(interval:onNewEvent:)`（或等價公開 API）的新事件提醒語意。
@MainActor
final class AgentActivityStoreNewEventTests: XCTestCase {
    private func makeEvent(
        id: UUID = UUID(),
        status: AgentActivityStatus,
        title: String = "task",
        occurredAt: Date = Date()
    ) -> AgentActivityEvent {
        AgentActivityEvent(
            id: id,
            provider: .claude,
            status: status,
            title: title,
            occurredAt: occurredAt)
    }

    /// 等待 `startPolling` 觸發的首次 refresh 完成（以 `lastRefreshedAt` 為準，不用 sleep）。
    private func waitForFirstRefresh(_ store: AgentActivityStore) async {
        for _ in 0..<5_000 {
            if store.lastRefreshedAt != nil { return }
            await Task.yield()
        }
        XCTFail("timed out waiting for first refresh (lastRefreshedAt still nil)")
    }

    /// 註冊 `onNewEvent`、吃掉首次 baseline poll，再停掉 timer，後續一律以 `refresh()` 驅動。
    private func beginPollingForNewEvents(
        store: AgentActivityStore,
        collector: NewEventCollector
    ) async {
        store.startPolling(interval: 86_400, onNewEvent: { event in
            collector.append(event)
        })
        await waitForFirstRefresh(store)
        store.stopPolling()
    }

    func test_first_refresh_establishes_baseline_without_notifying() async {
        let baselineID = UUID()
        let baseline = makeEvent(id: baselineID, status: .completed, title: "baseline")
        let provider = SequencedAgentActivityProvider(snapshots: [
            [baseline],
        ])
        let store = AgentActivityStore(activityProvider: provider)
        let collector = NewEventCollector()

        await beginPollingForNewEvents(store: store, collector: collector)

        XCTAssertEqual(store.events.map(\.id), [baselineID])
        XCTAssertTrue(
            collector.events.isEmpty,
            "首次 refresh/poll 僅建立 baseline，不得觸發 onNewEvent")
    }

    private func makeInputEvent(
        eventID: UUID = UUID(),
        requestID: UUID = UUID(),
        occurredAt: Date
    ) -> AgentActivityEvent {
        AgentActivityEvent(
            id: eventID,
            provider: .claude,
            status: .needsInput,
            title: "Choose",
            occurredAt: occurredAt,
            inputRequest: AgentInputRequest(
                requestID: requestID,
                questions: [AgentInputQuestion(
                    question: "Choose a mode",
                    header: "Mode",
                    options: [
                        AgentInputOption(label: "Fast", description: ""),
                        AgentInputOption(label: "Safe", description: ""),
                    ],
                    multiSelect: false)]))
    }

    func test_first_refresh_replays_only_fresh_input_request() async {
        let fresh = makeInputEvent(occurredAt: Date())
        let old = makeInputEvent(occurredAt: Date().addingTimeInterval(-301))
        let provider = SequencedAgentActivityProvider(snapshots: [[fresh, old]])
        let store = AgentActivityStore(activityProvider: provider)
        let collector = NewEventCollector()

        await beginPollingForNewEvents(store: store, collector: collector)

        XCTAssertEqual(collector.ids, [fresh.id])
    }

    func test_input_request_id_is_not_replayed_when_event_uuid_changes() async {
        let requestID = UUID()
        let first = makeInputEvent(requestID: requestID, occurredAt: Date())
        let replay = makeInputEvent(requestID: requestID, occurredAt: Date())
        let provider = SequencedAgentActivityProvider(snapshots: [
            [first],
            [replay],
        ])
        let store = AgentActivityStore(activityProvider: provider)
        let collector = NewEventCollector()

        await beginPollingForNewEvents(store: store, collector: collector)
        await store.refresh()

        XCTAssertEqual(collector.ids, [first.id])
    }

    func test_new_uuid_notifies_once_and_repeat_refresh_does_not_replay() async {
        let baselineID = UUID()
        let newID = UUID()
        let baseline = makeEvent(id: baselineID, status: .completed, title: "baseline")
        let newEvent = makeEvent(
            id: newID,
            status: .completed,
            title: "new",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_100))
        let provider = SequencedAgentActivityProvider(snapshots: [
            [baseline],
            [baseline, newEvent],
            [baseline, newEvent],
        ])
        let store = AgentActivityStore(activityProvider: provider)
        let collector = NewEventCollector()

        await beginPollingForNewEvents(store: store, collector: collector)
        XCTAssertTrue(collector.events.isEmpty, "baseline 階段不得提醒")

        await store.refresh()
        XCTAssertEqual(collector.ids, [newID], "後續新增 UUID 應觸發一次 onNewEvent")

        await store.refresh()
        XCTAssertEqual(collector.ids, [newID], "重複 refresh 不得重播同一 UUID")
    }

    func test_running_and_stopped_are_not_user_notifiable() async {
        let runningID = UUID()
        let stoppedID = UUID()
        let running = makeEvent(id: runningID, status: .running, title: "run")
        let stopped = makeEvent(
            id: stoppedID,
            status: .stopped,
            title: "stop",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_200))
        let provider = SequencedAgentActivityProvider(snapshots: [
            [],
            [running],
            [running, stopped],
        ])
        let store = AgentActivityStore(activityProvider: provider)
        let collector = NewEventCollector()

        await beginPollingForNewEvents(store: store, collector: collector)
        XCTAssertTrue(collector.events.isEmpty)

        await store.refresh()
        XCTAssertTrue(
            collector.events.isEmpty,
            "running 不視為使用者提醒狀態")

        await store.refresh()
        XCTAssertTrue(
            collector.events.isEmpty,
            "stopped 不視為使用者提醒狀態")
    }

    func test_notifiable_statuses_trigger_on_new_uuid() async {
        let startedID = UUID()
        let completedID = UUID()
        let needsInputID = UUID()
        let failedID = UUID()
        let resourceLimitID = UUID()

        let started = makeEvent(id: startedID, status: .started, title: "started")
        let completed = makeEvent(
            id: completedID,
            status: .completed,
            title: "completed",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_301))
        let needsInput = makeEvent(
            id: needsInputID,
            status: .needsInput,
            title: "needsInput",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_302))
        let failed = makeEvent(
            id: failedID,
            status: .failed,
            title: "failed",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_303))
        let resourceLimit = makeEvent(
            id: resourceLimitID,
            status: .resourceLimit,
            title: "resourceLimit",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_304))

        // 每一步只新增一個可提醒狀態事件，鎖定 started/completed/needsInput/failed/resourceLimit。
        let provider = SequencedAgentActivityProvider(snapshots: [
            [],
            [started],
            [started, completed],
            [started, completed, needsInput],
            [started, completed, needsInput, failed],
            [started, completed, needsInput, failed, resourceLimit],
        ])
        let store = AgentActivityStore(activityProvider: provider)
        let collector = NewEventCollector()

        await beginPollingForNewEvents(store: store, collector: collector)
        XCTAssertTrue(collector.events.isEmpty)

        await store.refresh()
        await store.refresh()
        await store.refresh()
        await store.refresh()
        await store.refresh()

        XCTAssertEqual(
            collector.ids,
            [startedID, completedID, needsInputID, failedID, resourceLimitID],
            "可提醒狀態的新 UUID 各應觸發一次")
        XCTAssertEqual(
            collector.statuses,
            [.started, .completed, .needsInput, .failed, .resourceLimit])
    }

    func test_mixed_snapshot_only_notifies_notifiable_new_uuids() async {
        let runningID = UUID()
        let completedID = UUID()
        let stoppedID = UUID()
        let failedID = UUID()

        let running = makeEvent(id: runningID, status: .running, title: "running")
        let completed = makeEvent(
            id: completedID,
            status: .completed,
            title: "completed",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_401))
        let stopped = makeEvent(
            id: stoppedID,
            status: .stopped,
            title: "stopped",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_402))
        let failed = makeEvent(
            id: failedID,
            status: .failed,
            title: "failed",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_403))

        let provider = SequencedAgentActivityProvider(snapshots: [
            [running],
            [running, completed, stopped, failed],
        ])
        let store = AgentActivityStore(activityProvider: provider)
        let collector = NewEventCollector()

        await beginPollingForNewEvents(store: store, collector: collector)
        XCTAssertTrue(collector.events.isEmpty, "baseline 中的 running 不得提醒")

        await store.refresh()

        XCTAssertEqual(
            Set(collector.ids),
            Set([completedID, failedID]),
            "同一次 snapshot 只提醒可通知狀態的新 UUID（completed/failed），略過 running/stopped")
        XCTAssertFalse(collector.ids.contains(runningID))
        XCTAssertFalse(collector.ids.contains(stoppedID))
        XCTAssertEqual(collector.events.count, 2)
    }
}
