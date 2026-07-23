import Foundation
import XCTest
@testable import VoidNotchKit

final class AlertSoundPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempDirectory: URL!
    private var preferences: AlertSoundPreferences!

    override func setUpWithError() throws {
        suiteName = "VoidNotch.AlertSoundPreferencesTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        preferences = AlertSoundPreferences(userDefaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testStatusAndPackCategoryMappings() {
        let expected: [(AgentActivityStatus, AlertSoundCategory, String)] = [
            (.started, .sessionStart, "session.start"),
            (.completed, .taskComplete, "task.complete"),
            (.needsInput, .inputRequired, "input.required"),
            (.failed, .taskError, "task.error"),
            (.resourceLimit, .resourceLimit, "resource.limit"),
        ]

        for (status, category, packCategoryName) in expected {
            XCTAssertEqual(AlertSoundCategory(status: status), category)
            XCTAssertEqual(category.packCategoryName, packCategoryName)
        }
        XCTAssertNil(AlertSoundCategory(status: .running))
        XCTAssertNil(AlertSoundCategory(status: .stopped))
        XCTAssertNil(AlertSoundCategory(status: nil as AgentActivityStatus?))
    }

    func testDefaultAndDamagedKindUseSoundPack() {
        XCTAssertEqual(preferences.selection(for: .taskComplete), .soundPack)
        defaults.set(
            "unknown",
            forKey: "VoidNotch.notifications.sound.taskComplete.kind")
        XCTAssertEqual(preferences.selection(for: .taskComplete), .soundPack)
    }

    func testSystemAndLocalSelectionsRoundTrip() throws {
        let soundFile = tempDirectory.appendingPathComponent("custom.aiff")
        try Data([0x00, 0x01]).write(to: soundFile)

        let system = AlertSoundSelection(kind: .system, value: "Ping")
        let local = AlertSoundSelection(kind: .localFile, value: soundFile.path)
        preferences.setSelection(system, for: .sessionStart)
        preferences.setSelection(local, for: .taskError)

        XCTAssertEqual(preferences.selection(for: .sessionStart), system)
        XCTAssertEqual(preferences.selection(for: .taskError), local)
        XCTAssertEqual(preferences.resolvedLocalFileURL(for: .taskError), soundFile)
    }

    func testSelectionUsesStableSeparatedKeys() {
        preferences.setSelection(
            AlertSoundSelection(kind: .system, value: "Tink"),
            for: .inputRequired)

        XCTAssertEqual(
            defaults.string(forKey: "VoidNotch.notifications.sound.inputRequired.kind"),
            "system")
        XCTAssertEqual(
            defaults.string(forKey: "VoidNotch.notifications.sound.inputRequired.value"),
            "Tink")
    }

    func testCategoriesRemainIsolated() {
        preferences.setSelection(
            AlertSoundSelection(kind: .system, value: "Glass"),
            for: .inputRequired)

        XCTAssertEqual(
            preferences.selection(for: .inputRequired),
            AlertSoundSelection(kind: .system, value: "Glass"))
        XCTAssertEqual(preferences.selection(for: .sessionStart), .soundPack)
        XCTAssertEqual(preferences.selection(for: .taskComplete), .soundPack)
        XCTAssertEqual(preferences.selection(for: .taskError), .soundPack)
        XCTAssertEqual(preferences.selection(for: .resourceLimit), .soundPack)
    }

    func testLocalFileResolutionRejectsEmptyRelativeMissingAndDirectoryPaths() {
        let rejectedPaths = [
            "",
            "relative/sound.aiff",
            tempDirectory.appendingPathComponent("missing.aiff").path,
            tempDirectory.path,
        ]

        for path in rejectedPaths {
            preferences.setSelection(
                AlertSoundSelection(kind: .localFile, value: path),
                for: .resourceLimit)
            XCTAssertNil(preferences.resolvedLocalFileURL(for: .resourceLimit), path)
        }
    }

    func testLocalFileResolutionAcceptsReadableAbsoluteRegularFile() throws {
        let soundFile = tempDirectory.appendingPathComponent("readable.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: soundFile)
        preferences.setSelection(
            AlertSoundSelection(kind: .localFile, value: soundFile.path),
            for: .taskComplete)

        XCTAssertEqual(preferences.resolvedLocalFileURL(for: .taskComplete), soundFile)
        XCTAssertEqual(preferences.resolvedLocalFileURL(from: soundFile.path), soundFile)
    }
}
