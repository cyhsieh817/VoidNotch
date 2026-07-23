import CryptoKit
import Foundation

/// The parsed Antigravity CLI OAuth token file.
public struct AgyCLITokenFile: Sendable, Equatable {
    public var accessToken: String?
    public var tokenType: String?
    public var refreshToken: String?
    public var expiryRFC3339: String?
    public var authMethod: String?
    public let fileSHA256: String

    public init(
        accessToken: String?,
        tokenType: String?,
        refreshToken: String?,
        expiryRFC3339: String?,
        authMethod: String?,
        fileSHA256: String)
    {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.refreshToken = refreshToken
        self.expiryRFC3339 = expiryRFC3339
        self.authMethod = authMethod
        self.fileSHA256 = fileSHA256
    }

    public var expiryDate: Date? {
        guard let expiryRFC3339 else { return nil }
        return AgyCLIOAuthBridge.date(fromRFC3339: expiryRFC3339)
    }
}

public enum AgyCLIOAuthBridgeError: Error, Equatable {
    case fileMissing
    case malformedTokenFile
    case conflictDetected
    case writeVerificationFailed
}

public enum AgyCLIOAuthBridge {
    public static func defaultTokenFileURL(home: URL) -> URL {
        home
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("antigravity-cli", isDirectory: true)
            .appendingPathComponent("antigravity-oauth-token")
    }

    public static func defaultTokenFileURL() -> URL {
        defaultTokenFileURL(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public static func parseTokenFile(_ data: Data) throws -> AgyCLITokenFile {
        let root: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any]
            else {
                throw AgyCLIOAuthBridgeError.malformedTokenFile
            }
            root = dictionary
        } catch let error as AgyCLIOAuthBridgeError {
            throw error
        } catch {
            throw AgyCLIOAuthBridgeError.malformedTokenFile
        }

        guard let token = root["token"] as? [String: Any] else {
            throw AgyCLIOAuthBridgeError.malformedTokenFile
        }

        return AgyCLITokenFile(
            accessToken: token["access_token"] as? String,
            tokenType: token["token_type"] as? String,
            refreshToken: token["refresh_token"] as? String,
            expiryRFC3339: token["expiry"] as? String,
            authMethod: root["auth_method"] as? String,
            fileSHA256: sha256Hex(data))
    }

    public static func readTokenFile(at url: URL, fileManager: FileManager) throws -> AgyCLITokenFile {
        let data = try readRawData(at: url, fileManager: fileManager)
        return try parseTokenFile(data)
    }

    public static func readTokenFile(at url: URL) throws -> AgyCLITokenFile {
        try readTokenFile(at: url, fileManager: .default)
    }

    public static func rfc3339String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    public static func date(fromRFC3339 string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    @discardableResult
    public static func applyCredentials(
        accessToken: String?,
        refreshToken: String,
        expiry: Date?,
        to url: URL,
        expectedSHA256: String?,
        fileManager: FileManager) throws -> AgyCLITokenFile
    {
        let originalData = try readRawData(at: url, fileManager: fileManager)
        let currentSHA256 = sha256Hex(originalData)
        if let expectedSHA256, expectedSHA256 != currentSHA256 {
            throw AgyCLIOAuthBridgeError.conflictDetected
        }

        let rootObject: Any
        do {
            rootObject = try JSONSerialization.jsonObject(with: originalData)
        } catch {
            throw AgyCLIOAuthBridgeError.malformedTokenFile
        }

        guard var root = rootObject as? [String: Any],
              var token = root["token"] as? [String: Any]
        else {
            throw AgyCLIOAuthBridgeError.malformedTokenFile
        }

        token["access_token"] = accessToken ?? ""
        token["refresh_token"] = refreshToken
        token["expiry"] = rfc3339String(from: expiry ?? Date(timeIntervalSince1970: 0))
        if token["token_type"] == nil {
            token["token_type"] = "Bearer"
        }
        root["token"] = token

        let updatedData: Data
        do {
            updatedData = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        } catch {
            throw AgyCLIOAuthBridgeError.writeVerificationFailed
        }

        let backupURL = URL(fileURLWithPath: "\(url.path).vn-prev")
        do {
            try originalData.write(to: backupURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: backupURL.path)
            try updatedData.write(to: url, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: url.path)
        } catch {
            throw AgyCLIOAuthBridgeError.writeVerificationFailed
        }

        do {
            return try readTokenFile(at: url, fileManager: fileManager)
        } catch {
            throw AgyCLIOAuthBridgeError.writeVerificationFailed
        }
    }

    @discardableResult
    public static func applyCredentials(
        accessToken: String?,
        refreshToken: String,
        expiry: Date?,
        to url: URL,
        expectedSHA256: String?) throws -> AgyCLITokenFile
    {
        try applyCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiry: expiry,
            to: url,
            expectedSHA256: expectedSHA256,
            fileManager: .default)
    }

    private static func readRawData(at url: URL, fileManager: FileManager) throws -> Data {
        guard let data = fileManager.contents(atPath: url.path) else {
            if fileManager.fileExists(atPath: url.path) {
                throw AgyCLIOAuthBridgeError.malformedTokenFile
            }
            throw AgyCLIOAuthBridgeError.fileMissing
        }
        return data
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
