import CryptoKit
import Foundation
import XCTest
@testable import VoidNotchKit

final class AgyCLIOAuthBridgeTests: XCTestCase {
    private let fileManager = FileManager.default
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("voidnotch-agy-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? fileManager.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func test_defaultTokenFileURL_usesAgyCLIPath() {
        let home = URL(fileURLWithPath: "/tmp/fake-home", isDirectory: true)
        XCTAssertEqual(
            AgyCLIOAuthBridge.defaultTokenFileURL(home: home).path,
            "/tmp/fake-home/.gemini/antigravity-cli/antigravity-oauth-token")
    }

    func test_parseTokenFile_readsFieldsAndPreservesUnknownValuesInSource() throws {
        let data = Data(#"{"token":{"access_token":"ya29.FAKE","token_type":"Bearer","refresh_token":"1//FAKE","expiry":"2026-07-23T02:06:00.123456Z","future_token_field":{"x":1}},"auth_method":"builtin","future_field":{"x":1}}"#.utf8)

        let parsed = try AgyCLIOAuthBridge.parseTokenFile(data)

        XCTAssertEqual(parsed.accessToken, "ya29.FAKE")
        XCTAssertEqual(parsed.tokenType, "Bearer")
        XCTAssertEqual(parsed.refreshToken, "1//FAKE")
        XCTAssertEqual(parsed.expiryRFC3339, "2026-07-23T02:06:00.123456Z")
        XCTAssertEqual(parsed.authMethod, "builtin")
        XCTAssertEqual(parsed.fileSHA256, sha256Hex(data))
        XCTAssertNotNil(parsed.expiryDate)
    }

    func test_parseTokenFile_rejectsNonObjectAndMissingToken() {
        assertBridgeError(tryParse(Data("[]".utf8)), equals: .malformedTokenFile)
        assertBridgeError(tryParse(Data(#"{"auth_method":"builtin"}"#.utf8)), equals: .malformedTokenFile)
    }

    func test_rfc3339_acceptsFractionalSecondsOffsetsAndZ() {
        let fractional = AgyCLIOAuthBridge.date(fromRFC3339: "2026-07-23T02:06:00.123456Z")
        let noFraction = AgyCLIOAuthBridge.date(fromRFC3339: "2026-07-23T02:06:00Z")
        let offset = AgyCLIOAuthBridge.date(fromRFC3339: "2026-07-23T10:06:00.123456+08:00")

        XCTAssertNotNil(fractional)
        XCTAssertNotNil(noFraction)
        XCTAssertNotNil(offset)
        XCTAssertEqual(fractional, offset)
    }

    func test_rfc3339_roundTripsWithinOneMillisecond() {
        let source = Date(timeIntervalSince1970: 1_752_000_000.123)
        let encoded = AgyCLIOAuthBridge.rfc3339String(from: source)
        let decoded = AgyCLIOAuthBridge.date(fromRFC3339: encoded)

        XCTAssertTrue(encoded.hasSuffix("Z"))
        XCTAssertTrue(encoded.contains("."))
        XCTAssertNotNil(decoded)
        XCTAssertLessThan(abs(decoded!.timeIntervalSince(source)), 0.001)
    }

    func test_applyCredentials_preservesUnknownFieldsAndExistingMetadata() throws {
        let url = tokenFileURL()
        let originalData = Data(#"{"token":{"access_token":"old.FAKE","token_type":"Custom","refresh_token":"old-refresh.FAKE","expiry":"2026-07-23T02:06:00Z","future_token_field":{"nested":true}},"auth_method":"builtin","future_field":{"x":1}}"#.utf8)
        try originalData.write(to: url)
        let expectedSHA256 = try AgyCLIOAuthBridge.readTokenFile(at: url, fileManager: fileManager).fileSHA256

        let result = try AgyCLIOAuthBridge.applyCredentials(
            accessToken: "new.FAKE",
            refreshToken: "new-refresh.FAKE",
            expiry: Date(timeIntervalSince1970: 1_752_000_000.123),
            to: url,
            expectedSHA256: expectedSHA256,
            fileManager: fileManager)

        XCTAssertEqual(result.accessToken, "new.FAKE")
        XCTAssertEqual(result.refreshToken, "new-refresh.FAKE")
        XCTAssertEqual(result.tokenType, "Custom")
        XCTAssertEqual(result.authMethod, "builtin")

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let token = try XCTUnwrap(root["token"] as? [String: Any])
        XCTAssertEqual((root["future_field"] as? [String: Any])?["x"] as? Int, 1)
        XCTAssertEqual((token["future_token_field"] as? [String: Any])?["nested"] as? Bool, true)
    }

    func test_applyCredentials_CASMismatchThrowsConflictAndLeavesFileUnchanged() throws {
        let url = tokenFileURL()
        let originalData = validTokenData()
        try originalData.write(to: url)

        XCTAssertThrowsError(
            try AgyCLIOAuthBridge.applyCredentials(
                accessToken: "new.FAKE",
                refreshToken: "new-refresh.FAKE",
                expiry: nil,
                to: url,
                expectedSHA256: "not-the-current-hash",
                fileManager: fileManager)) { error in
            XCTAssertEqual(error as? AgyCLIOAuthBridgeError, .conflictDetected)
        }
        XCTAssertEqual(try Data(contentsOf: url), originalData)
    }

    func test_readTokenFile_missingFileThrowsFileMissing() {
        XCTAssertThrowsError(try AgyCLIOAuthBridge.readTokenFile(at: tokenFileURL(), fileManager: fileManager)) { error in
            XCTAssertEqual(error as? AgyCLIOAuthBridgeError, .fileMissing)
        }
    }

    func test_readTokenFile_invalidJSONThrowsMalformedTokenFile() throws {
        try Data("{".utf8).write(to: tokenFileURL())

        XCTAssertThrowsError(try AgyCLIOAuthBridge.readTokenFile(at: tokenFileURL(), fileManager: fileManager)) { error in
            XCTAssertEqual(error as? AgyCLIOAuthBridgeError, .malformedTokenFile)
        }
    }

    func test_applyCredentials_missingFileThrowsFileMissing() {
        XCTAssertThrowsError(
            try AgyCLIOAuthBridge.applyCredentials(
                accessToken: "new.FAKE",
                refreshToken: "new-refresh.FAKE",
                expiry: nil,
                to: tokenFileURL(),
                expectedSHA256: nil,
                fileManager: fileManager)) { error in
            XCTAssertEqual(error as? AgyCLIOAuthBridgeError, .fileMissing)
        }
    }

    func test_applyCredentials_writesOriginalBytesToBackup() throws {
        let url = tokenFileURL()
        let originalData = validTokenData()
        try originalData.write(to: url)

        _ = try AgyCLIOAuthBridge.applyCredentials(
            accessToken: "new.FAKE",
            refreshToken: "new-refresh.FAKE",
            expiry: Date(timeIntervalSince1970: 1_752_000_000),
            to: url,
            expectedSHA256: nil,
            fileManager: fileManager)

        let backupURL = URL(fileURLWithPath: "\(url.path).vn-prev")
        XCTAssertEqual(try Data(contentsOf: backupURL), originalData)
    }

    func test_applyCredentials_setsTokenAndBackupPermissionsToPrivate() throws {
        let url = tokenFileURL()
        try validTokenData().write(to: url)

        _ = try AgyCLIOAuthBridge.applyCredentials(
            accessToken: "new.FAKE",
            refreshToken: "new-refresh.FAKE",
            expiry: nil,
            to: url,
            expectedSHA256: nil,
            fileManager: fileManager)

        let backupURL = URL(fileURLWithPath: "\(url.path).vn-prev")
        let tokenPermissions = try XCTUnwrap(
            fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        let backupPermissions = try XCTUnwrap(
            fileManager.attributesOfItem(atPath: backupURL.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(tokenPermissions.intValue & 0o777, 0o600)
        XCTAssertEqual(backupPermissions.intValue & 0o777, 0o600)
    }

    func test_applyCredentials_nilExpiryUsesFrozenSentinelAndReReadsNewValues() throws {
        let url = tokenFileURL()
        try Data(#"{"token":{"access_token":"old.FAKE","refresh_token":"old-refresh.FAKE"}}"#.utf8).write(to: url)

        let result = try AgyCLIOAuthBridge.applyCredentials(
            accessToken: nil,
            refreshToken: "new-refresh.FAKE",
            expiry: nil,
            to: url,
            expectedSHA256: nil,
            fileManager: fileManager)

        XCTAssertEqual(result.accessToken, "")
        XCTAssertEqual(result.refreshToken, "new-refresh.FAKE")
        XCTAssertEqual(result.tokenType, "Bearer")
        XCTAssertEqual(result.expiryRFC3339, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(result.expiryDate, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(try AgyCLIOAuthBridge.readTokenFile(at: url, fileManager: fileManager), result)
    }

    private func tokenFileURL() -> URL {
        temporaryDirectory.appendingPathComponent("antigravity-oauth-token")
    }

    private func validTokenData() -> Data {
        Data(#"{"token":{"access_token":"old.FAKE","token_type":"Bearer","refresh_token":"old-refresh.FAKE","expiry":"2026-07-23T02:06:00Z"},"auth_method":"builtin"}"#.utf8)
    }

    private func tryParse(_ data: Data) -> Result<AgyCLITokenFile, Error> {
        do {
            return .success(try AgyCLIOAuthBridge.parseTokenFile(data))
        } catch {
            return .failure(error)
        }
    }

    private func assertBridgeError(
        _ result: Result<AgyCLITokenFile, Error>,
        equals expected: AgyCLIOAuthBridgeError,
        file: StaticString = #filePath,
        line: UInt = #line)
    {
        guard case let .failure(error) = result else {
            return XCTFail("Expected bridge error", file: file, line: line)
        }
        XCTAssertEqual(error as? AgyCLIOAuthBridgeError, expected, file: file, line: line)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
