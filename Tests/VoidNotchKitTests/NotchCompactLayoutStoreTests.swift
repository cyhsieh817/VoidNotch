import XCTest
@testable import VoidNotchKit

final class NotchCompactLayoutStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: NotchCompactLayoutStore!

    override func setUp() {
        suiteName = "VoidNotch.Tests.NotchCompactLayoutStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = NotchCompactLayoutStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
    }

    func test_preferredSide_defaults_when_empty() {
        XCTAssertEqual(store.preferredSide(for: "system"), .leading)
        XCTAssertEqual(store.preferredSide(for: "token"), .trailing)
        XCTAssertEqual(store.preferredSide(for: "agent-activity"), .trailing)
        XCTAssertEqual(store.preferredSide(for: "unknown-widget"), .trailing)
    }

    func test_setPreferredSide_persists_and_reads_back() {
        store.setPreferredSide(.trailing, for: "system")
        XCTAssertEqual(store.preferredSide(for: "system"), .trailing)
        store.setPreferredSide(.leading, for: "token")
        XCTAssertEqual(store.preferredSide(for: "token"), .leading)
        XCTAssertTrue(store.isWidget("token", on: .leading))
        XCTAssertFalse(store.isWidget("token", on: .trailing))
    }

    func test_setWidget_enabled_assigns_side_disabled_flips() {
        store.setWidget("system", on: .trailing, enabled: true)
        XCTAssertEqual(store.preferredSide(for: "system"), .trailing)
        store.setWidget("system", on: .trailing, enabled: false)
        XCTAssertEqual(store.preferredSide(for: "system"), .leading)
    }

    func test_maxWidth_clamps_above_upper_bound() {
        store.setMaxWidth(9999, for: .leading)
        XCTAssertEqual(store.maxWidth(for: .leading), NotchCompactLayout.maxWidth)
    }

    func test_maxWidth_clamps_below_lower_bound() {
        store.setMaxWidth(1, for: .trailing)
        XCTAssertEqual(store.maxWidth(for: .trailing), NotchCompactLayout.minWidth)
    }

    func test_maxWidth_empty_input_uses_side_default() {
        XCTAssertEqual(store.maxWidth(for: .leading), NotchCompactLayout.defaultLeadingWidth)
        XCTAssertEqual(store.maxWidth(for: .trailing), NotchCompactLayout.defaultTrailingWidth)
    }

    func test_contentHeight_clamps_and_empty_default() {
        XCTAssertEqual(store.contentHeight, NotchCompactLayout.defaultHeight)
        store.setContentHeight(0)
        XCTAssertEqual(store.contentHeight, NotchCompactLayout.minHeight)
        store.setContentHeight(1000)
        XCTAssertEqual(store.contentHeight, NotchCompactLayout.maxHeight)
        store.setContentHeight(24)
        XCTAssertEqual(store.contentHeight, 24)
    }

    func test_pinned_defaults_and_set() {
        XCTAssertTrue(store.isPinned(.leading))
        XCTAssertFalse(store.isPinned(.trailing))
        store.setPinned(false, side: .leading)
        store.setPinned(true, side: .trailing)
        XCTAssertFalse(store.isPinned(.leading))
        XCTAssertTrue(store.isPinned(.trailing))
    }

    func test_revision_bumps_on_mutations() {
        let before = store.revision
        store.setPreferredSide(.leading, for: "token")
        XCTAssertEqual(store.revision, before + 1)
        store.setMaxWidth(120, for: .leading)
        XCTAssertEqual(store.revision, before + 2)
    }
}
