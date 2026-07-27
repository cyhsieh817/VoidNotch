import Foundation
import XCTest
@testable import VoidNotchKit

final class SelfUpdaterTests: XCTestCase {
    func testVerifyCandidateRunsChecksInOrderAndPropagatesNonZeroExit() throws {
        let expectedSteps = [
            "codesign",
            "designated-requirement",
            "designated-requirement",
            "stapler",
            "spctl",
        ]

        for failingIndex in expectedSteps.indices {
            let runner = StubRunner(responses: expectedVerifyResponses(failingIndex: failingIndex))
            let updater = SelfUpdater(runner: runner)

            XCTAssertThrowsError(
                try updater.verifyCandidate(
                    URL(fileURLWithPath: "/tmp/VoidNotch.app"),
                    againstRunning: URL(fileURLWithPath: "/tmp/Current.app"))) { error in
                XCTAssertEqual(error as? SelfUpdateError, .verify(step: expectedSteps[failingIndex]))
            }

            XCTAssertEqual(runner.calls.map(\.launchPath), Array(expectedSteps.prefix(failingIndex + 1)).map { path in
                switch path {
                case "codesign": return "/usr/bin/codesign"
                case "designated-requirement": return "/usr/bin/codesign"
                case "stapler": return "/usr/bin/xcrun"
                default: return "/usr/bin/spctl"
                }
            })
            if failingIndex >= 1 {
                XCTAssertEqual(runner.calls[1].args, ["-d", "-r-", "/tmp/Current.app"])
            }
        }
    }

    func testSpctlOutputMustContainAccepted() throws {
        let runner = StubRunner(responses: [
            (0, "verified"),
            (0, "designated => anchor apple generic and identifier \"dev.voidnotch.VoidNotch\""),
            (0, "verified"),
            (0, "ticket stapled"),
            (0, "rejected"),
        ])
        let updater = SelfUpdater(runner: runner)

        XCTAssertThrowsError(
            try updater.verifyCandidate(
                URL(fileURLWithPath: "/tmp/VoidNotch.app"),
                againstRunning: URL(fileURLWithPath: "/tmp/Current.app"))) { error in
            XCTAssertEqual(error as? SelfUpdateError, .verify(step: "spctl"))
        }
    }

    /// codesign -R= 只吃裸 requirement：帶「designated =>」前綴實測必 parse error（2026-07-24 真機驗證）。
    func testDesignatedRequirementArgumentStripsPrefix() throws {
        let runner = StubRunner(responses: expectedVerifyResponses(failingIndex: -1))
        let updater = SelfUpdater(runner: runner)

        try updater.verifyCandidate(
            URL(fileURLWithPath: "/tmp/VoidNotch.app"),
            againstRunning: URL(fileURLWithPath: "/tmp/Current.app"))

        let requirementArg = runner.calls[2].args.first { $0.hasPrefix("-R=") }
        XCTAssertEqual(
            requirementArg,
            "-R=anchor apple generic and identifier \"dev.voidnotch.VoidNotch\"")
        XCTAssertFalse(requirementArg?.contains("designated =>") ?? true)
    }

    func testSha256HexMatchesKnownBytes() throws {
        let fileURL = makeTemporaryURL("sha256-input")
        defer { preserveTemporaryItem(fileURL) }
        try Data("abc".utf8).write(to: fileURL)

        let updater = SelfUpdater(runner: StubRunner(responses: []))

        XCTAssertEqual(
            try updater.sha256Hex(of: fileURL),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testPreflightRejectsAppTranslocation() {
        let updater = SelfUpdater(runner: StubRunner(responses: []))
        let result = updater.preflight(
            bundleURL: URL(fileURLWithPath: "/private/var/AppTranslocation/ABC/App.app"))

        guard case .preflight("translocation") = result else {
            return XCTFail("expected App Translocation preflight error, got \(String(describing: result))")
        }
    }

    func testPreflightRejectsNonWritableParent() throws {
        let parent = makeTemporaryURL("non-writable-parent")
        defer { preserveTemporaryItem(parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)

        let updater = SelfUpdater(runner: StubRunner(responses: []))
        let result = updater.preflight(bundleURL: parent.appendingPathComponent("VoidNotch.app"))

        guard case .preflight("parent-not-writable") = result else {
            return XCTFail("expected non-writable preflight error, got \(String(describing: result))")
        }
    }

    func testAppUpdateInfoWithoutSha256DecodesAsNil() throws {
        let data = Data(#"{"version":"0.8.0","url":"https://labgrimoire.com/VoidNotch.zip"}"#.utf8)
        let info = try JSONDecoder().decode(AppUpdateInfo.self, from: data)

        XCTAssertEqual(info.version, "0.8.0")
        XCTAssertNil(info.sha256)
    }

    func testHelperScriptHasExpectedGuardrails() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helper = repoRoot.appendingPathComponent("resources/update/voidnotch-update-helper.sh")
        let contents = try String(contentsOf: helper, encoding: .utf8)

        XCTAssertTrue(contents.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(contents.contains("set -eu"))
        XCTAssertTrue(contents.contains("parent_dir=$(dirname \"$current_app\")"))
        XCTAssertTrue(contents.contains("staged_new=\"$parent_dir/.VoidNotch-update-$$.app\""))
        XCTAssertTrue(contents.contains("/usr/bin/ditto \"$new_app\" \"$staged_new\""))
        XCTAssertTrue(contents.contains("local_backup=\"$parent_dir/.VoidNotch-backup-$$.app\""))
        XCTAssertFalse(contents.contains("mv \"$new_app\" \"$current_app\""))
        XCTAssertFalse(contents.contains("mv \"$current_app\" \"$backup_dir/VoidNotch-backup.app\""))
        XCTAssertTrue(contents.contains("mv \"$local_backup\" \"$current_app\""))
        XCTAssertTrue(contents.contains("mv \"$local_backup\" \"$backup_dir/VoidNotch-backup.app\""))
        XCTAssertTrue(contents.contains("rolling back"))
        XCTAssertTrue(contents.contains("failed-$(date +%s).app"))
        XCTAssertTrue(contents.contains("VoidNotch-backup.app"))
    }

    func testControllerHasUpdateSecurityGuardrails() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = repoRoot.appendingPathComponent("App/Monitors/SelfUpdateController.swift")
        let contents = try String(contentsOf: controller, encoding: .utf8)

        XCTAssertTrue(contents.contains("return host == suffix || host.hasSuffix(\".\" + suffix)"))
        XCTAssertTrue(contents.contains("sha256 missing or malformed"))
        XCTAssertTrue(contents.contains("expectedHash.utf8.count == 64"))
        XCTAssertTrue(contents.contains("expectedHash.utf8.allSatisfy"))
        XCTAssertTrue(contents.contains("CFBundleShortVersionString"))
        XCTAssertTrue(contents.contains("SemverCompare.isNewer("))
        XCTAssertTrue(contents.contains("remote: normalizedCandidateVersion"))
        XCTAssertTrue(contents.contains("than: normalizedCurrentVersion"))
        XCTAssertTrue(contents.contains("normalizeVersion(update.version)"))
    }

    func testControllerChecksVersionBeforeRemovingQuarantine() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = repoRoot.appendingPathComponent("App/Monitors/SelfUpdateController.swift")
        let contents = try String(contentsOf: controller, encoding: .utf8)

        guard let versionRange = contents.range(of: "let normalizedCandidateVersion = normalizeVersion(candidateVersion)"),
              let removeQuarantineRange = contents.range(of: "try updater.removeQuarantine(candidate)")
        else {
            return XCTFail("expected controller version gate and quarantine removal")
        }

        XCTAssertLessThan(
            contents.distance(from: contents.startIndex, to: versionRange.lowerBound),
            contents.distance(from: contents.startIndex, to: removeQuarantineRange.lowerBound))
    }

    private func expectedVerifyResponses(failingIndex: Int) -> [(Int32, String)] {
        let successful = [
            (Int32(0), "verified"),
            (Int32(0), "Executable=/tmp/Current.app\ndesignated => anchor apple generic and identifier \"dev.voidnotch.VoidNotch\""),
            (Int32(0), "verified"),
            (Int32(0), "ticket stapled"),
            (Int32(0), "accepted"),
        ]
        return successful.enumerated().map { index, response in
            index == failingIndex ? (Int32(1), "failed") : response
        }
    }

    private func makeTemporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchSelfUpdaterTests-\(UUID().uuidString)-\(name)")
    }

    private func preserveTemporaryItem(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let preserved = url.deletingLastPathComponent()
            .appendingPathComponent("_DELETE_\(url.lastPathComponent)")
        try? FileManager.default.moveItem(at: url, to: preserved)
    }
}

private final class StubRunner: UpdateProcessRunning, @unchecked Sendable {
    struct Call {
        let launchPath: String
        let args: [String]
    }

    private let responses: [(Int32, String)]
    private var responseIndex = 0
    private(set) var calls: [Call] = []

    init(responses: [(Int32, String)]) {
        self.responses = responses
    }

    func run(_ launchPath: String, _ args: [String]) throws -> (Int32, String) {
        calls.append(Call(launchPath: launchPath, args: args))
        guard responseIndex < responses.count else {
            throw NSError(domain: "StubRunner", code: 1)
        }
        defer { responseIndex += 1 }
        return responses[responseIndex]
    }
}
