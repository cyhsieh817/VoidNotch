//
//  CodexBarTokenAccountManager.swift — CodexBarCore token-account bridge
//

import Foundation
import VoidNotchKit

#if canImport(CodexBarCore)
import CodexBarCore

public struct CodexBarTokenAccountManager: TokenAccountManaging {
    private let store: any ProviderTokenAccountStoring
    private let antigravityCredentialsStore: AntigravityOAuthCredentialsStore
    private let metadataStore: ProviderTokenAccountMetadataStore

    public init(
        store: any ProviderTokenAccountStoring = FileTokenAccountStore(),
        antigravityCredentialsStore: AntigravityOAuthCredentialsStore = AntigravityOAuthCredentialsStore())
    {
        self.store = store
        self.antigravityCredentialsStore = antigravityCredentialsStore
        self.metadataStore = ProviderTokenAccountMetadataStore()
    }

    public func loadAccounts(for provider: TokenProviderKind) async throws -> [ProviderAccount] {
        let codexProvider = try Self.codexProvider(for: provider)
        guard TokenAccountSupportCatalog.support(for: codexProvider) != nil else {
            throw TokenAccountManagementError.unsupportedProvider(provider)
        }

        let data = try store.loadAccounts()[codexProvider]
        guard let data else { return [] }
        let activeIndex = data.clampedActiveIndex()
        let metadata = try metadataStore.loadMetadata(for: codexProvider)
        return data.accounts.enumerated().map { index, account in
            Self.map(
                account,
                provider: provider,
                isActive: index == activeIndex,
                metadata: metadata[account.id.uuidString])
        }
    }

    public func loadAccountUsages(for provider: TokenProviderKind) async throws -> [ProviderAccountUsage] {
        let codexProvider = try Self.codexProvider(for: provider)
        guard TokenAccountSupportCatalog.support(for: codexProvider) != nil else {
            throw TokenAccountManagementError.unsupportedProvider(provider)
        }

        let data = try store.loadAccounts()[codexProvider]
        guard let data, !data.accounts.isEmpty else { return [] }

        let activeIndex = data.clampedActiveIndex()
        let metadata = try metadataStore.loadMetadata(for: codexProvider)
        let usageProvider = CodexBarTokenUsageProvider(tokenAccountStore: store)
        var accountUsages: [ProviderAccountUsage] = []

        for (index, tokenAccount) in data.accounts.enumerated() {
            let account = Self.map(
                tokenAccount,
                provider: provider,
                isActive: index == activeIndex,
                metadata: metadata[tokenAccount.id.uuidString])
            if account.isDisabled {
                accountUsages.append(
                    ProviderAccountUsage(
                        account: account,
                        usage: ProviderUsage(
                            provider: provider,
                            status: .unavailable,
                            errorMessage: account.displaySubtitle)))
                continue
            }
            do {
                let usage = try await usageProvider.fetchUsage(for: provider, selectedAccount: tokenAccount)
                if let skipReason = Self.skipReason(from: usage.errorMessage) {
                    try? metadataStore.setMetadata(
                        ProviderTokenAccountMetadata(isDisabled: true, disabledReason: skipReason),
                        for: tokenAccount.id,
                        provider: codexProvider)
                    var disabledAccount = account
                    disabledAccount.isDisabled = true
                    disabledAccount.disabledReason = skipReason
                    accountUsages.append(
                        ProviderAccountUsage(
                            account: disabledAccount,
                            usage: ProviderUsage(
                                provider: provider,
                                status: .unavailable,
                                errorMessage: skipReason)))
                    continue
                }
                accountUsages.append(
                    ProviderAccountUsage(
                        account: account,
                        usage: usage))
            } catch {
                if let skipReason = Self.skipReason(from: error.localizedDescription) {
                    try? metadataStore.setMetadata(
                        ProviderTokenAccountMetadata(isDisabled: true, disabledReason: skipReason),
                        for: tokenAccount.id,
                        provider: codexProvider)
                    var disabledAccount = account
                    disabledAccount.isDisabled = true
                    disabledAccount.disabledReason = skipReason
                    accountUsages.append(
                        ProviderAccountUsage(
                            account: disabledAccount,
                            usage: ProviderUsage(
                                provider: provider,
                                status: .unavailable,
                                errorMessage: skipReason)))
                    continue
                }
                accountUsages.append(
                    ProviderAccountUsage(
                        account: account,
                        usage: ProviderUsage(
                            provider: provider,
                            status: .unavailable,
                            errorMessage: error.localizedDescription)))
            }
        }

        return accountUsages
    }

    public func setActiveAccount(_ accountID: UUID, for provider: TokenProviderKind) async throws {
        let codexProvider = try Self.codexProvider(for: provider)
        var accountsByProvider = try store.loadAccounts()
        guard let data = accountsByProvider[codexProvider],
              let index = data.accounts.firstIndex(where: { $0.id == accountID })
        else {
            throw TokenAccountManagementError.accountNotFound
        }
        let metadata = try metadataStore.loadMetadata(for: codexProvider)
        if metadata[accountID.uuidString]?.isDisabled == true {
            throw TokenAccountManagementError.accountDisabled
        }

        var accounts = data.accounts
        let selectedAccount = Self.copy(accounts[index], lastUsed: Date().timeIntervalSince1970)
        try syncSharedAntigravityCredentialsIfNeeded(selectedAccount, provider: provider)
        accounts[index] = selectedAccount
        accountsByProvider[codexProvider] = ProviderTokenAccountData(
            version: data.version,
            accounts: accounts,
            activeIndex: index)
        try store.storeAccounts(accountsByProvider)
    }

    public func setAccountDisabled(
        _ accountID: UUID,
        disabled: Bool,
        reason: String?,
        for provider: TokenProviderKind) async throws
    {
        let codexProvider = try Self.codexProvider(for: provider)
        var accountsByProvider = try store.loadAccounts()
        guard let data = accountsByProvider[codexProvider],
              let index = data.accounts.firstIndex(where: { $0.id == accountID })
        else {
            throw TokenAccountManagementError.accountNotFound
        }

        if disabled {
            try metadataStore.setMetadata(
                ProviderTokenAccountMetadata(
                    isDisabled: true,
                    disabledReason: Self.normalized(reason) ?? "Skipped account"),
                for: accountID,
                provider: codexProvider)
        } else {
            try metadataStore.removeMetadata(for: accountID, provider: codexProvider)
        }

        let metadata = try metadataStore.loadMetadata(for: codexProvider)
        let activeIndex = data.clampedActiveIndex()

        if disabled, activeIndex == index {
            if let nextIndex = Self.firstEnabledIndex(in: data.accounts, preferredIndex: index, metadata: metadata) {
                try syncSharedAntigravityCredentialsIfNeeded(data.accounts[nextIndex], provider: provider)
                accountsByProvider[codexProvider] = ProviderTokenAccountData(
                    version: data.version,
                    accounts: data.accounts,
                    activeIndex: nextIndex)
                try store.storeAccounts(accountsByProvider)
            } else {
                try clearSharedAntigravityCredentialsIfMatching(data.accounts[index], provider: provider)
            }
        } else if !disabled,
                  metadata[data.accounts[activeIndex].id.uuidString]?.isDisabled == true
        {
            try syncSharedAntigravityCredentialsIfNeeded(data.accounts[index], provider: provider)
            accountsByProvider[codexProvider] = ProviderTokenAccountData(
                version: data.version,
                accounts: data.accounts,
                activeIndex: index)
            try store.storeAccounts(accountsByProvider)
        }
    }

    public func deleteAccount(_ accountID: UUID, for provider: TokenProviderKind) async throws {
        let codexProvider = try Self.codexProvider(for: provider)
        var accountsByProvider = try store.loadAccounts()
        guard let data = accountsByProvider[codexProvider],
              let index = data.accounts.firstIndex(where: { $0.id == accountID })
        else {
            throw TokenAccountManagementError.accountNotFound
        }

        var accounts = data.accounts
        let removedAccount = accounts[index]
        accounts.remove(at: index)
        if accounts.isEmpty {
            try clearSharedAntigravityCredentialsIfMatching(removedAccount, provider: provider)
            accountsByProvider.removeValue(forKey: codexProvider)
        } else {
            let nextActiveIndex: Int
            if data.activeIndex == index {
                nextActiveIndex = min(index, accounts.count - 1)
            } else if data.activeIndex > index {
                nextActiveIndex = data.activeIndex - 1
            } else {
                nextActiveIndex = data.activeIndex
            }
            let metadata = try metadataStore.loadMetadata(for: codexProvider)
            let clampedActiveIndex = min(max(nextActiveIndex, 0), accounts.count - 1)
            let nextEnabledIndex = Self.firstEnabledIndex(
                in: accounts,
                preferredIndex: clampedActiveIndex,
                metadata: metadata)
            let finalActiveIndex = nextEnabledIndex ?? clampedActiveIndex
            if data.activeIndex == index, let nextEnabledIndex {
                try syncSharedAntigravityCredentialsIfNeeded(accounts[nextEnabledIndex], provider: provider)
            } else if data.activeIndex == index {
                try clearSharedAntigravityCredentialsIfMatching(removedAccount, provider: provider)
            }
            accountsByProvider[codexProvider] = ProviderTokenAccountData(
                version: data.version,
                accounts: accounts,
                activeIndex: finalActiveIndex)
        }
        try store.storeAccounts(accountsByProvider)
        try metadataStore.removeMetadata(for: accountID, provider: codexProvider)
    }

    public func importAccount(for provider: TokenProviderKind) async throws -> ProviderAccount? {
        guard provider == .antigravity else {
            throw TokenAccountManagementError.unsupportedProvider(provider)
        }
        guard let credentials = try antigravityCredentialsStore.load() else {
            throw TokenAccountManagementError.noImportableAccount(provider)
        }
        return try upsertAntigravityAccount(credentials)
    }

    public func importAccounts(_ accountImport: ProviderAccountImport, for provider: TokenProviderKind) async throws -> [ProviderAccount] {
        guard provider == .antigravity else {
            throw TokenAccountManagementError.unsupportedProvider(provider)
        }

        let imports = try Self.parseAntigravityAccountImports(accountImport)
        guard !imports.isEmpty else {
            throw TokenAccountManagementError.invalidImportData(provider)
        }

        return try imports.map { accountImport in
            try upsertAntigravityAccount(
                accountImport.credentials,
                labelOverride: accountImport.label)
        }
    }

    public func exportAccounts(_ accountIDs: [UUID], for provider: TokenProviderKind) async throws -> ProviderAccountExport {
        guard provider == .antigravity else {
            throw TokenAccountManagementError.unsupportedProvider(provider)
        }

        let codexProvider = try Self.codexProvider(for: provider)
        guard let data = try store.loadAccounts()[codexProvider] else {
            throw TokenAccountManagementError.noExportableAccount(provider)
        }

        let selectedIDs = Set(accountIDs)
        let accounts = selectedIDs.isEmpty
            ? data.accounts
            : data.accounts.filter { selectedIDs.contains($0.id) }
        let exportAccounts = accounts.compactMap { account -> AntigravityExportAccount? in
            guard let credentials = AntigravityOAuthCredentialsStore.credentials(fromTokenAccountValue: account.token),
                  let refreshToken = Self.normalized(credentials.refreshToken)
            else {
                return nil
            }
            return AntigravityExportAccount(
                email: Self.normalized(credentials.resolvedAccountEmail) ?? Self.normalized(account.externalIdentifier),
                refreshToken: refreshToken)
        }

        guard !exportAccounts.isEmpty else {
            throw TokenAccountManagementError.noExportableAccount(provider)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encodedData = try encoder.encode(AntigravityAccountsExport(accounts: exportAccounts))
        guard let payload = String(data: encodedData, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return ProviderAccountExport(
            provider: provider,
            fileName: "agy-accounts-export.json",
            payload: payload,
            accountCount: exportAccounts.count)
    }

    private func upsertAntigravityAccount(
        _ credentials: AntigravityOAuthCredentials,
        labelOverride: String? = nil) throws -> ProviderAccount
    {
        let token = try AntigravityOAuthCredentialsStore.tokenAccountValue(for: credentials)
        let email = Self.normalized(credentials.resolvedAccountEmail)
        var accountsByProvider = try store.loadAccounts()
        let data = accountsByProvider[.antigravity] ?? ProviderTokenAccountData(version: 1, accounts: [], activeIndex: 0)
        let label = labelOverride ?? email ?? "Google Account \(data.accounts.count + 1)"
        var accounts = data.accounts

        if let email,
           let index = accounts.firstIndex(where: {
               Self.normalized($0.externalIdentifier)?.caseInsensitiveCompare(email) == .orderedSame
           })
        {
            accounts[index] = Self.copy(
                accounts[index],
                label: label,
                token: token,
                externalIdentifier: email,
                lastUsed: Date().timeIntervalSince1970)
            accountsByProvider[.antigravity] = ProviderTokenAccountData(
                version: data.version,
                accounts: accounts,
                activeIndex: index)
            try store.storeAccounts(accountsByProvider)
            try antigravityCredentialsStore.save(credentials)
            return Self.map(accounts[index], provider: .antigravity, isActive: true)
        }

        let account = ProviderTokenAccount(
            id: UUID(),
            label: label,
            token: token,
            addedAt: Date().timeIntervalSince1970,
            lastUsed: Date().timeIntervalSince1970,
            externalIdentifier: email)
        accounts.append(account)
        accountsByProvider[.antigravity] = ProviderTokenAccountData(
            version: data.version,
            accounts: accounts,
            activeIndex: accounts.count - 1)
        try store.storeAccounts(accountsByProvider)
        try antigravityCredentialsStore.save(credentials)
        return Self.map(account, provider: .antigravity, isActive: true)
    }

    private func syncSharedAntigravityCredentialsIfNeeded(
        _ account: ProviderTokenAccount,
        provider: TokenProviderKind) throws
    {
        guard provider == .antigravity,
              let credentials = AntigravityOAuthCredentialsStore.credentials(fromTokenAccountValue: account.token)
        else {
            return
        }
        try antigravityCredentialsStore.save(credentials)
    }

    private func clearSharedAntigravityCredentialsIfMatching(
        _ account: ProviderTokenAccount,
        provider: TokenProviderKind) throws
    {
        guard provider == .antigravity,
              let removedCredentials = AntigravityOAuthCredentialsStore.credentials(fromTokenAccountValue: account.token)
        else {
            return
        }
        try antigravityCredentialsStore.deleteIfPresent { sharedCredentials in
            Self.credentialsMatch(sharedCredentials, removedCredentials)
        }
    }

    private static func codexProvider(for provider: TokenProviderKind) throws -> UsageProvider {
        switch provider {
        case .antigravity:
            return .antigravity
        case .claude, .codex, .openAI, .gemini, .copilot, .cursor, .grok, .vertexAI, .bedrock:
            throw TokenAccountManagementError.unsupportedProvider(provider)
        }
    }

    private static func map(
        _ account: ProviderTokenAccount,
        provider: TokenProviderKind,
        isActive: Bool,
        metadata: ProviderTokenAccountMetadata? = nil) -> ProviderAccount
    {
        ProviderAccount(
            id: account.id,
            provider: provider,
            label: account.label,
            externalIdentifier: account.externalIdentifier,
            addedAt: Date(timeIntervalSince1970: account.addedAt),
            lastUsedAt: account.lastUsed.map { Date(timeIntervalSince1970: $0) },
            isActive: isActive,
            isDisabled: metadata?.isDisabled == true,
            disabledReason: metadata?.isDisabled == true ? metadata?.disabledReason : nil)
    }

    private static func firstEnabledIndex(
        in accounts: [ProviderTokenAccount],
        preferredIndex: Int,
        metadata: [String: ProviderTokenAccountMetadata]) -> Int?
    {
        guard !accounts.isEmpty else { return nil }
        let clampedIndex = min(max(preferredIndex, 0), accounts.count - 1)
        let orderedIndices = Array(clampedIndex..<accounts.count) + Array(0..<clampedIndex)
        return orderedIndices.first { index in
            metadata[accounts[index].id.uuidString]?.isDisabled != true
        }
    }

    private static func copy(
        _ account: ProviderTokenAccount,
        label: String? = nil,
        token: String? = nil,
        externalIdentifier: String? = nil,
        lastUsed: TimeInterval? = nil) -> ProviderTokenAccount
    {
        ProviderTokenAccount(
            id: account.id,
            label: label ?? account.label,
            token: token ?? account.token,
            addedAt: account.addedAt,
            lastUsed: lastUsed ?? account.lastUsed,
            externalIdentifier: externalIdentifier ?? account.externalIdentifier,
            organizationID: account.organizationID)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private static func skipReason(from errorMessage: String?) -> String? {
        guard let normalized = normalized(errorMessage)?.lowercased() else { return nil }
        if normalized.contains("403")
            || normalized.contains("forbidden")
            || normalized.contains("banned")
            || normalized.contains("ban")
        {
            return "Skipped after ban/403 response"
        }
        return nil
    }

    private static func credentialsMatch(
        _ lhs: AntigravityOAuthCredentials,
        _ rhs: AntigravityOAuthCredentials) -> Bool
    {
        if let lhsRefreshToken = normalized(lhs.refreshToken),
           let rhsRefreshToken = normalized(rhs.refreshToken)
        {
            return lhsRefreshToken == rhsRefreshToken
        }
        if let lhsAccessToken = normalized(lhs.accessToken),
           let rhsAccessToken = normalized(rhs.accessToken)
        {
            return lhsAccessToken == rhsAccessToken
        }
        if let lhsEmail = normalized(lhs.resolvedAccountEmail),
           let rhsEmail = normalized(rhs.resolvedAccountEmail)
        {
            return lhsEmail.caseInsensitiveCompare(rhsEmail) == .orderedSame
        }
        return false
    }

    private static func parseAntigravityAccountImports(
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

        guard Self.normalized(rawValue) != nil else {
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

struct ProviderTokenAccountMetadata: Codable, Sendable, Equatable {
    var isDisabled: Bool
    var disabledReason: String?
}

struct ProviderTokenAccountMetadataStore: @unchecked Sendable {
    private static let fileLock = NSLock()

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadMetadata(for provider: UsageProvider) throws -> [String: ProviderTokenAccountMetadata] {
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }
        return try loadFileUnlocked().providers[provider.rawValue] ?? [:]
    }

    func setMetadata(
        _ metadata: ProviderTokenAccountMetadata?,
        for accountID: UUID,
        provider: UsageProvider) throws
    {
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }

        var file = try loadFileUnlocked()
        var providerMetadata = file.providers[provider.rawValue] ?? [:]
        providerMetadata[accountID.uuidString] = metadata
        if providerMetadata.isEmpty {
            file.providers.removeValue(forKey: provider.rawValue)
        } else {
            file.providers[provider.rawValue] = providerMetadata
        }
        try storeFileUnlocked(file)
    }

    func removeMetadata(for accountID: UUID, provider: UsageProvider) throws {
        try setMetadata(nil, for: accountID, provider: provider)
    }

    private func loadFileUnlocked() throws -> ProviderTokenAccountMetadataFile {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ProviderTokenAccountMetadataFile(version: 1, providers: [:])
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ProviderTokenAccountMetadataFile.self, from: data)
    }

    private func storeFileUnlocked(_ file: ProviderTokenAccountMetadataFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: fileURL, options: [.atomic])
        #if os(macOS) || os(Linux)
        try fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: fileURL.path)
        #endif
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("VoidNotch", isDirectory: true)
            .appendingPathComponent("provider-account-metadata.json")
    }
}

private struct ProviderTokenAccountMetadataFile: Codable {
    var version: Int
    var providers: [String: [String: ProviderTokenAccountMetadata]]
}

private struct AntigravityAccountsExport: Encodable {
    var accounts: [AntigravityExportAccount]
}

private struct AntigravityExportAccount: Encodable {
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

private struct ParsedAntigravityAccountImport {
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
#else
public struct CodexBarTokenAccountManager: TokenAccountManaging {
    public init() {}

    public func loadAccounts(for provider: TokenProviderKind) async throws -> [ProviderAccount] {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }

    public func setActiveAccount(_ accountID: UUID, for provider: TokenProviderKind) async throws {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }

    public func deleteAccount(_ accountID: UUID, for provider: TokenProviderKind) async throws {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }
}
#endif
