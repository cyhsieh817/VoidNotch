//
//  CodexBarTokenAccountManager.swift — CodexBarCore token-account bridge
//

import Foundation
import OSLog
import VoidNotchKit

#if canImport(CodexBarCore)
import CodexBarCore

public struct CodexBarTokenAccountManager: TokenAccountManaging {
    private static let log = Logger(subsystem: "dev.voidnotch", category: "account-manager")

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
                    do {
                        try metadataStore.setMetadata(
                            ProviderTokenAccountMetadata(isDisabled: true, disabledReason: skipReason),
                            for: tokenAccount.id,
                            provider: codexProvider)
                    } catch {
                        Self.log.error("Account disable persistence failed provider=\(codexProvider.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
                    }
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
                    do {
                        try metadataStore.setMetadata(
                            ProviderTokenAccountMetadata(isDisabled: true, disabledReason: skipReason),
                            for: tokenAccount.id,
                            provider: codexProvider)
                    } catch {
                        Self.log.error("Account disable persistence failed provider=\(codexProvider.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
                    }
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

        // 主來源＝agy CLI token 檔。僅在該檔「不存在」時才回退舊的 .codexbar 共享憑證；
        // 檔存在但格式壞或缺 refresh token 一律明確報錯，不靜默改匯入另一個舊帳號。
        let agyTokenFile: AgyCLITokenFile?
        do {
            agyTokenFile = try AgyCLIOAuthBridge.readTokenFile(
                at: AgyCLIOAuthBridge.defaultTokenFileURL())
        } catch AgyCLIOAuthBridgeError.fileMissing {
            agyTokenFile = nil
        } catch {
            throw TokenAccountManagementError.noImportableAccount(provider)
        }

        if let tokenFile = agyTokenFile {
            guard let refreshToken = Self.normalized(tokenFile.refreshToken) else {
                throw TokenAccountManagementError.noImportableAccount(provider)
            }
            var credentials = AntigravityOAuthCredentials(
                accessToken: tokenFile.accessToken,
                refreshToken: refreshToken,
                expiryDate: tokenFile.expiryDate)
            let expiryIsUsable = tokenFile.expiryDate == nil
                || tokenFile.expiryDate! > Date().addingTimeInterval(60)
            if let accessToken = Self.normalized(tokenFile.accessToken), expiryIsUsable {
                var request = URLRequest(url: AntigravityOAuthConfig.userInfoURL)
                request.httpMethod = "GET"
                request.timeoutInterval = 5
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                if let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
                   let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data),
                   let payload = json as? [String: Any],
                   let email = payload["email"] as? String
                {
                    credentials.email = email
                }
            }
            return try upsertAntigravityAccount(credentials)
        }

        guard let credentials = try antigravityCredentialsStore.load() else {
            throw TokenAccountManagementError.noImportableAccount(provider)
        }
        return try upsertAntigravityAccount(credentials)
    }

    public func applyAccountToAgyCLI(_ accountID: UUID, for provider: TokenProviderKind) async throws {
        guard provider == .antigravity else {
            throw TokenAccountManagementError.unsupportedProvider(provider)
        }

        guard let data = try store.loadAccounts()[.antigravity],
              let account = data.accounts.first(where: { $0.id == accountID })
        else {
            throw TokenAccountManagementError.accountNotFound
        }
        guard let credentials = AntigravityOAuthCredentialsStore.credentials(fromTokenAccountValue: account.token),
              let refreshToken = Self.normalized(credentials.refreshToken)
        else {
            throw TokenAccountManagementError.accountMissingRefreshToken
        }

        let tokenFileURL = AgyCLIOAuthBridge.defaultTokenFileURL()
        let tokenFile: AgyCLITokenFile
        do {
            tokenFile = try AgyCLIOAuthBridge.readTokenFile(at: tokenFileURL)
        } catch AgyCLIOAuthBridgeError.fileMissing {
            throw TokenAccountManagementError.agyTokenFileMissing
        } catch {
            throw error
        }

        do {
            // 只交付 refresh token：清空 access token 並把 expiry 設為過期（nil→1970 sentinel），
            // 強制 agy CLI 下次啟動用它自己內嵌的 client 重新換發，不沿用可能屬於別帳號的舊 access token。
            try AgyCLIOAuthBridge.applyCredentials(
                accessToken: nil,
                refreshToken: refreshToken,
                expiry: nil,
                to: tokenFileURL,
                expectedSHA256: tokenFile.fileSHA256)
        } catch AgyCLIOAuthBridgeError.conflictDetected {
            throw TokenAccountManagementError.agyTokenFileConflict
        } catch AgyCLIOAuthBridgeError.fileMissing {
            throw TokenAccountManagementError.agyTokenFileMissing
        } catch {
            throw error
        }

        try antigravityCredentialsStore.save(credentials)
    }

    public func importAccounts(_ accountImport: ProviderAccountImport, for provider: TokenProviderKind) async throws -> [ProviderAccount] {
        guard provider == .antigravity else {
            throw TokenAccountManagementError.unsupportedProvider(provider)
        }

        let imports = try AntigravityAccountCodec.parseAntigravityAccountImports(accountImport)
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

        if let refreshToken = Self.normalized(credentials.refreshToken),
           let index = accounts.firstIndex(where: {
               guard let existingCredentials = AntigravityOAuthCredentialsStore.credentials(fromTokenAccountValue: $0.token),
                     let existingRefreshToken = Self.normalized(existingCredentials.refreshToken)
               else {
                   return false
               }
               return existingRefreshToken == refreshToken
           })
        {
            accounts[index] = Self.copy(
                accounts[index],
                label: labelOverride ?? email ?? accounts[index].label,
                token: token,
                externalIdentifier: email ?? accounts[index].externalIdentifier,
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

    static func normalized(_ value: String?) -> String? {
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

    public func applyAccountToAgyCLI(_ accountID: UUID, for provider: TokenProviderKind) async throws {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }
}
#endif
