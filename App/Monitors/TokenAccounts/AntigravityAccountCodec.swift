//
//  AntigravityAccountCodec.swift
//

#if canImport(CodexBarCore)
import Foundation
import CodexBarCore
import VoidNotchKit

struct AntigravityAccountsExport: Encodable {
    var accounts: [AntigravityExportAccount]
}

struct AntigravityExportAccount: Encodable {
    var email: String?
    var refreshToken: String

    private enum CodingKeys: String, CodingKey {
        case email
        case refreshToken = "refresh_token"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(refreshToken, forKey: .refreshToken)
    }
}

struct ParsedAntigravityAccountImport {
    var credentials: AntigravityOAuthCredentials
    var label: String?
}

private struct AntigravityAccountImportWrapper: Decodable {
    var accounts: [AntigravityAccountImportItem]

    private enum CodingKeys: String, CodingKey {
        case accounts
    }
}

private struct AntigravityAccountImportItem: Decodable {
    var email: String?
    var name: String?
    var customLabel: String?
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var expiryDateMilliseconds: Double?
    var token: AntigravityAccountImportToken?

    var parsedAccountImport: ParsedAntigravityAccountImport? {
        let resolvedAccessToken = Self.normalized(token?.accessToken) ?? Self.normalized(accessToken)
        let resolvedRefreshToken = Self.normalized(token?.refreshToken) ?? Self.normalized(refreshToken)
        guard resolvedAccessToken != nil || resolvedRefreshToken != nil else { return nil }

        let resolvedEmail = Self.normalized(email) ?? Self.normalized(token?.email)
        let expiryDate = Self.expiryDate(fromMilliseconds: token?.expiryDateMilliseconds ?? expiryDateMilliseconds)
        return ParsedAntigravityAccountImport(
            credentials: AntigravityOAuthCredentials(
                accessToken: resolvedAccessToken,
                refreshToken: resolvedRefreshToken,
                expiryDate: expiryDate,
                idToken: Self.normalized(idToken),
                email: resolvedEmail),
            label: Self.normalized(customLabel) ?? Self.normalized(name) ?? resolvedEmail)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.customLabel =
            try container.decodeIfPresent(String.self, forKey: .customLabelSnake)
            ?? container.decodeIfPresent(String.self, forKey: .customLabelCamel)
        self.accessToken =
            try container.decodeIfPresent(String.self, forKey: .accessTokenSnake)
            ?? container.decodeIfPresent(String.self, forKey: .accessTokenCamel)
        self.refreshToken =
            try container.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
            ?? container.decodeIfPresent(String.self, forKey: .refreshTokenCamel)
        self.idToken =
            try container.decodeIfPresent(String.self, forKey: .idTokenSnake)
            ?? container.decodeIfPresent(String.self, forKey: .idTokenCamel)
        self.expiryDateMilliseconds =
            try container.decodeFlexibleMilliseconds(forKey: .expiryDateSnake)
            ?? container.decodeFlexibleMilliseconds(forKey: .expiryTimestampSnake)
            ?? container.decodeFlexibleMilliseconds(forKey: .expiresAtCamel)
        self.token = try container.decodeIfPresent(AntigravityAccountImportToken.self, forKey: .token)
    }

    private enum CodingKeys: String, CodingKey {
        case email
        case name
        case token
        case customLabelSnake = "custom_label"
        case customLabelCamel = "customLabel"
        case accessTokenSnake = "access_token"
        case accessTokenCamel = "accessToken"
        case refreshTokenSnake = "refresh_token"
        case refreshTokenCamel = "refreshToken"
        case idTokenSnake = "id_token"
        case idTokenCamel = "idToken"
        case expiryDateSnake = "expiry_date"
        case expiryTimestampSnake = "expiry_timestamp"
        case expiresAtCamel = "expiresAt"
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private static func expiryDate(fromMilliseconds value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }
}

private struct AntigravityAccountImportToken: Decodable {
    var email: String?
    var accessToken: String?
    var refreshToken: String?
    var expiryDateMilliseconds: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.accessToken =
            try container.decodeIfPresent(String.self, forKey: .accessTokenSnake)
            ?? container.decodeIfPresent(String.self, forKey: .accessTokenCamel)
        self.refreshToken =
            try container.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
            ?? container.decodeIfPresent(String.self, forKey: .refreshTokenCamel)
        self.expiryDateMilliseconds =
            try container.decodeFlexibleMilliseconds(forKey: .expiryDateSnake)
            ?? container.decodeFlexibleMilliseconds(forKey: .expiryTimestampSnake)
            ?? container.decodeFlexibleMilliseconds(forKey: .expiresAtCamel)
    }

    private enum CodingKeys: String, CodingKey {
        case email
        case accessTokenSnake = "access_token"
        case accessTokenCamel = "accessToken"
        case refreshTokenSnake = "refresh_token"
        case refreshTokenCamel = "refreshToken"
        case expiryDateSnake = "expiry_date"
        case expiryTimestampSnake = "expiry_timestamp"
        case expiresAtCamel = "expiresAt"
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleMilliseconds(forKey key: Key) throws -> Double? {
        if let double = try decodeIfPresent(Double.self, forKey: key) {
            return double
        }
        if let int = try decodeIfPresent(Int.self, forKey: key) {
            return Double(int)
        }
        if let string = try decodeIfPresent(String.self, forKey: key),
           let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return double
        }
        return nil
    }
}

private extension AntigravityOAuthCredentials {
    var hasUsableToken: Bool {
        self.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || self.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

enum AntigravityAccountCodec {
    static func parseAntigravityAccountImports(
        _ accountImport: ProviderAccountImport) throws -> [ParsedAntigravityAccountImport]
    {
        let rawValue = accountImport.normalizedRawValue
        guard !rawValue.isEmpty else {
            throw TokenAccountManagementError.invalidImportData(.antigravity)
        }

        if let data = rawValue.data(using: .utf8) {
            let decoder = JSONDecoder()
            if let wrapper = try? decoder.decode(AntigravityAccountImportWrapper.self, from: data),
               !wrapper.accounts.isEmpty
            {
                let parsed = wrapper.accounts.compactMap(\.parsedAccountImport)
                guard !parsed.isEmpty else {
                    throw TokenAccountManagementError.invalidImportData(.antigravity)
                }
                return parsed
            }

            if let items = try? decoder.decode([AntigravityAccountImportItem].self, from: data),
               !items.isEmpty
            {
                let parsed = items.compactMap(\.parsedAccountImport)
                guard !parsed.isEmpty else {
                    throw TokenAccountManagementError.invalidImportData(.antigravity)
                }
                return parsed
            }

            if let credentials = try? decoder.decode(AntigravityOAuthCredentials.self, from: data),
               credentials.hasUsableToken
            {
                return [
                    ParsedAntigravityAccountImport(
                        credentials: credentials,
                        label: accountImport.normalizedLabel),
                ]
            }
        }

        guard CodexBarTokenAccountManager.normalized(rawValue) != nil else {
            throw TokenAccountManagementError.invalidImportData(.antigravity)
        }
        return [
            ParsedAntigravityAccountImport(
                credentials: AntigravityOAuthCredentials(
                    accessToken: nil,
                    refreshToken: rawValue,
                    expiryDate: nil),
                label: accountImport.normalizedLabel),
        ]
    }
}
#endif
