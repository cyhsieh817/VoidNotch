import XCTest
@testable import VoidNotchKit

final class DisplaySelectionStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "DisplaySelectionStoreTests-\(UUID().uuidString)")!
        return d
    }

    func test_defaults_menubar_matches_current_behavior() {
        let d = freshDefaults()
        DisplaySelectionStore.registerDefaults(d)
        XCTAssertEqual(DisplaySelectionStore.items(for: .menubar, defaults: d),
                       [.system(.cpu), .system(.memory), .aiUsage, .agentActivity])
    }

    func test_defaults_gauge_four_slots() {
        let d = freshDefaults()
        DisplaySelectionStore.registerDefaults(d)
        XCTAssertEqual(DisplaySelectionStore.items(for: .gauge, defaults: d),
                       [.system(.cpu), .system(.memory), .system(.temperature), .aiUsage])
    }

    func test_gauge_truncates_to_max() {
        let d = freshDefaults()
        let seven: [DisplayItem] = [.system(.cpu), .system(.memory), .system(.disk),
                                    .system(.network), .system(.battery), .system(.gpu),
                                    .aiUsage]
        DisplaySelectionStore.setItems(seven, for: .gauge, defaults: d)
        XCTAssertEqual(
            DisplaySelectionStore.items(for: .gauge, defaults: d).count,
            DisplaySurface.gauge.maxItems)
    }

    /// 回歸守門：未達上限時 canAdd 必為 true。舊版 gauge 上限 4，選滿 4 項後所有未勾選的
    /// checkbox 會被靜默 disable，使用者按了沒反應也沒有任何說明（2026-07-14 回報的「空框按不動」）。
    func test_can_add_below_cap() {
        let d = freshDefaults()
        let five: [DisplayItem] = [.system(.cpu), .system(.memory), .system(.temperature),
                                   .system(.disk), .system(.network)]
        DisplaySelectionStore.setItems(five, for: .gauge, defaults: d)
        XCTAssertEqual(DisplaySelectionStore.items(for: .gauge, defaults: d).count, 5)
        XCTAssertTrue(DisplaySelectionStore.canAdd(for: .gauge, defaults: d))
    }

    func test_setItems_roundtrip_and_order_preserved() {
        let d = freshDefaults()
        let sel: [DisplayItem] = [.aiUsage, .system(.cpu), .agentActivity]
        DisplaySelectionStore.setItems(sel, for: .menubar, defaults: d)
        XCTAssertEqual(DisplaySelectionStore.items(for: .menubar, defaults: d), sel)
    }

    func test_min_one_cannot_remove_last() {
        let d = freshDefaults()
        DisplaySelectionStore.setItems([.system(.cpu)], for: .gauge, defaults: d)
        XCTAssertFalse(DisplaySelectionStore.canRemove(.system(.cpu), for: .gauge, defaults: d))
        // 設空集被拒 → 回退保留至少 1
        DisplaySelectionStore.setItems([], for: .gauge, defaults: d)
        XCTAssertGreaterThanOrEqual(DisplaySelectionStore.items(for: .gauge, defaults: d).count, 1)
    }

    func test_can_remove_when_more_than_one() {
        let d = freshDefaults()
        DisplaySelectionStore.setItems([.system(.cpu), .system(.memory)], for: .gauge, defaults: d)
        XCTAssertTrue(DisplaySelectionStore.canRemove(.system(.cpu), for: .gauge, defaults: d))
    }

    func test_corrupt_value_returns_default() {
        let d = freshDefaults()
        d.set("not-json-array", forKey: "VoidNotch.display.gauge.items")
        XCTAssertEqual(DisplaySelectionStore.items(for: .gauge, defaults: d),
                       DisplaySelectionStore.gaugeDefault)
    }

    func test_empty_or_all_unknown_keys_returns_default() {
        let d = freshDefaults()
        let data = try! JSONEncoder().encode(["system.bogus", "nope"])
        d.set(data, forKey: "VoidNotch.display.menubar.items")
        XCTAssertEqual(DisplaySelectionStore.items(for: .menubar, defaults: d),
                       DisplaySelectionStore.menubarDefault)
    }

    func test_encode_failure_preserves_existing_key() {
        let d = freshDefaults()
        let original: [DisplayItem] = [.system(.cpu), .system(.memory), .aiUsage]
        DisplaySelectionStore.setItems(original, for: .gauge, defaults: d)
        XCTAssertEqual(DisplaySelectionStore.items(for: .gauge, defaults: d), original)

        enum EncodeStubError: Error { case forced }
        DisplaySelectionStore.setItems(
            [.system(.disk), .system(.network)],
            for: .gauge,
            defaults: d,
            encode: { _ in throw EncodeStubError.forced })
        // encode 失敗不得寫入／移除 key → 舊值保留
        XCTAssertEqual(DisplaySelectionStore.items(for: .gauge, defaults: d), original)
        XCTAssertNotNil(d.data(forKey: DisplaySurface.gauge.storageKey))
    }

    func test_interleaved_writes_single_toggle_from_fresh_read() {
        let d = freshDefaults()
        // 路徑 A：設定頁快照 [A,B]
        DisplaySelectionStore.setItems([.system(.cpu), .system(.memory)], for: .gauge, defaults: d)
        // 路徑 B：右鍵選單寫入 [A,B,C]
        DisplaySelectionStore.setItems(
            [.system(.cpu), .system(.memory), .aiUsage], for: .gauge, defaults: d)

        // 設定頁應「重讀真值後單一 toggle」移除 A，結果 [B,C] 而非過期的 [B]
        var current = DisplaySelectionStore.items(for: .gauge, defaults: d)
        let a = DisplayItem.system(.cpu)
        XCTAssertTrue(DisplaySelectionStore.canRemove(a, for: .gauge, defaults: d))
        current.removeAll { $0 == a }
        DisplaySelectionStore.setItems(current, for: .gauge, defaults: d)

        XCTAssertEqual(
            DisplaySelectionStore.items(for: .gauge, defaults: d),
            [.system(.memory), .aiUsage])
    }

    func test_guard_boundaries_max_min_one() {
        let d = freshDefaults()
        let full: [DisplayItem] = [
            .system(.cpu), .system(.memory), .system(.temperature), .system(.disk),
            .system(.network), .aiUsage
        ]
        XCTAssertEqual(full.count, DisplaySurface.gauge.maxItems)
        DisplaySelectionStore.setItems(full, for: .gauge, defaults: d)
        XCTAssertEqual(
            DisplaySelectionStore.items(for: .gauge, defaults: d).count,
            DisplaySurface.gauge.maxItems)
        XCTAssertFalse(DisplaySelectionStore.canAdd(for: .gauge, defaults: d))

        DisplaySelectionStore.setItems([.system(.cpu)], for: .gauge, defaults: d)
        XCTAssertEqual(DisplaySelectionStore.items(for: .gauge, defaults: d).count, 1)
        XCTAssertFalse(DisplaySelectionStore.canRemove(.system(.cpu), for: .gauge, defaults: d))
    }
}
