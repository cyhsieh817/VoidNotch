import XCTest
@testable import VoidNotchKit

final class DisplayItemTests: XCTestCase {
    func test_storageKey_roundtrip_for_whole_catalog() {
        for item in DisplayItem.catalog {
            let key = item.storageKey
            XCTAssertEqual(DisplayItem(storageKey: key), item, "round-trip failed for \(key)")
        }
    }

    func test_known_storage_keys() {
        XCTAssertEqual(DisplayItem(storageKey: "system.cpu"), .system(.cpu))
        XCTAssertEqual(DisplayItem(storageKey: "aiUsage"), .aiUsage)
        XCTAssertEqual(DisplayItem(storageKey: "agentActivity"), .agentActivity)
        XCTAssertEqual(DisplayItem.aiUsage.storageKey, "aiUsage")
        XCTAssertEqual(DisplayItem.system(.temperature).storageKey, "system.temperature")
    }

    func test_unknown_key_returns_nil() {
        XCTAssertNil(DisplayItem(storageKey: "system.bogus"))
        XCTAssertNil(DisplayItem(storageKey: "nope"))
        XCTAssertNil(DisplayItem(storageKey: "system."))
    }

    func test_catalog_shape() {
        // 10 系統指標 + aiUsage + agentActivity = 12
        XCTAssertEqual(DisplayItem.catalog.count, 12)
        XCTAssertEqual(DisplayItem.catalog.first, .system(.cpu))
        XCTAssertEqual(DisplayItem.catalog.suffix(2), [.aiUsage, .agentActivity])
    }
}
