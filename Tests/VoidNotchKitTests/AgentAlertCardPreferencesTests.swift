import Foundation
import XCTest
@testable import VoidNotchKit

final class AgentAlertCardPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var preferences: AgentAlertCardPreferences!

    override func setUpWithError() throws {
        defaults = makeTestDefaults("AgentAlertCardPreferences")
        preferences = AgentAlertCardPreferences(userDefaults: defaults)
    }

    func testTextScaleDefaultsToOneWhenUnset() {
        XCTAssertEqual(preferences.textScale, 1.0)
    }

    func testTextScaleRoundTripsWithinRange() {
        preferences.textScale = 1.2
        XCTAssertEqual(preferences.textScale, 1.2, accuracy: 0.0001)
    }

    func testTextScaleClampsAboveMaximum() {
        preferences.textScale = 5.0
        XCTAssertEqual(preferences.textScale, AgentAlertCardPreferences.maximumTextScale)
    }

    func testTextScaleClampsBelowMinimum() {
        preferences.textScale = 0.1
        XCTAssertEqual(preferences.textScale, AgentAlertCardPreferences.minimumTextScale)
    }

    func testTextScaleClampsWrittenDirectlyToDefaults() {
        // 模擬非本類別寫入（例如舊版留下的壞值）：讀取仍須 clamp，不可信任原始儲存值。
        defaults.set(9.9, forKey: AgentAlertCardPreferences.Keys.textScale)
        XCTAssertEqual(preferences.textScale, AgentAlertCardPreferences.maximumTextScale)

        defaults.set(-1.0, forKey: AgentAlertCardPreferences.Keys.textScale)
        XCTAssertEqual(preferences.textScale, AgentAlertCardPreferences.minimumTextScale)
    }

    func testClampedTextScaleRejectsNonFiniteValues() {
        XCTAssertEqual(
            AgentAlertCardPreferences.clampedTextScale(.nan),
            AgentAlertCardPreferences.defaultTextScale)
        XCTAssertEqual(
            AgentAlertCardPreferences.clampedTextScale(.infinity),
            AgentAlertCardPreferences.defaultTextScale)
    }

    func testNotificationMirrorDefaultsToDisabled() {
        XCTAssertFalse(preferences.notificationMirrorEnabled)
    }

    func testNotificationMirrorRoundTrips() {
        preferences.notificationMirrorEnabled = true
        XCTAssertTrue(preferences.notificationMirrorEnabled)
        preferences.notificationMirrorEnabled = false
        XCTAssertFalse(preferences.notificationMirrorEnabled)
    }

    func testTextScalePresetsMatchDocumentedFourSteps() {
        XCTAssertEqual(
            AgentAlertTextScalePreset.allCases.map(\.rawValue).sorted(),
            [0.9, 1.0, 1.2, 1.4])
    }
}
