import XCTest
@testable import VoidNotchKit

@MainActor
final class TokenStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.voidnotch.token.\(UUID().uuidString)")!
    }

    func test_default_providers_when_empty() {
        let store = TokenStore(usageProvider: UnavailableTokenUsageProvider(), defaults: freshDefaults())
        XCTAssertEqual(store.selectedProviderKinds, TokenProviderKind.defaultVisible)
    }

    func test_enabling_provider_follows_canonical_order() {
        let store = TokenStore(providerKinds: [.claude],
                               usageProvider: UnavailableTokenUsageProvider(),
                               defaults: freshDefaults())
        store.setProvider(.codex, enabled: true)
        // defaultVisible 順序為 [.codex, .copilot, .claude, .antigravity, .grok]
        XCTAssertEqual(store.selectedProviderKinds, [.codex, .claude])
    }

    func test_cannot_disable_last_provider() {
        let store = TokenStore(providerKinds: [.codex],
                               usageProvider: UnavailableTokenUsageProvider(),
                               defaults: freshDefaults())
        XCTAssertFalse(store.canDisableProvider(.codex))
        store.setProvider(.codex, enabled: false)
        XCTAssertEqual(store.selectedProviderKinds, [.codex]) // 守門,維持不變
    }

    func test_selection_persists_across_instances() {
        let defaults = freshDefaults()
        let first = TokenStore(providerKinds: [.codex, .claude, .antigravity],
                               usageProvider: UnavailableTokenUsageProvider(),
                               defaults: defaults)
        first.setProvider(.claude, enabled: false)
        let second = TokenStore(usageProvider: UnavailableTokenUsageProvider(), defaults: defaults)
        XCTAssertFalse(second.selectedProviderKinds.contains(.claude))
    }

    func test_refresh_marks_static_providers_available() async {
        let snap = ProviderUsage(provider: .codex, status: .available, sessionTokens: 100)
        let store = TokenStore(providers: [snap])
        await store.refresh()
        XCTAssertEqual(store.providers.first?.status, .available)
        XCTAssertNotNil(store.lastRefreshedAt)
    }

    func test_compact_display_provider_persists() {
        let defaults = freshDefaults()
        let first = TokenStore(providerKinds: [.codex, .copilot, .claude],
                               usageProvider: UnavailableTokenUsageProvider(),
                               defaults: defaults)
        first.setCompactDisplayProvider(.copilot)

        let second = TokenStore(providerKinds: [.codex, .copilot, .claude],
                                usageProvider: UnavailableTokenUsageProvider(),
                                defaults: defaults)
        XCTAssertEqual(second.compactDisplayProvider, .copilot)
    }

    func test_compact_display_auto_rotates_enabled_providers() {
        let store = TokenStore(providers: [
            ProviderUsage(provider: .codex, status: .available, usedPercent: 10),
            ProviderUsage(provider: .copilot, status: .available, usedPercent: 20),
        ], defaults: freshDefaults())

        let base = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(store.compactDisplayUsage(at: base)?.provider, .codex)
        XCTAssertEqual(
            store.compactDisplayUsage(at: base.addingTimeInterval(TokenStore.compactRotationInterval))?.provider,
            .copilot)
    }

    func test_compact_display_provider_clears_when_disabled() {
        let store = TokenStore(providerKinds: [.codex, .copilot],
                               usageProvider: UnavailableTokenUsageProvider(),
                               defaults: freshDefaults())
        store.setCompactDisplayProvider(.copilot)
        store.setProvider(.copilot, enabled: false)

        XCTAssertNil(store.compactDisplayProvider)
        XCTAssertEqual(store.compactDisplayUsage(at: Date(timeIntervalSinceReferenceDate: 0))?.provider, .codex)
    }

    func test_provider_accounts_load_from_manager() async {
        let activeID = UUID()
        let manager = InMemoryTokenAccountManager(accounts: [
            .antigravity: [
                ProviderAccount(
                    id: activeID,
                    provider: .antigravity,
                    label: "primary@example.com",
                    externalIdentifier: "primary@example.com",
                    isActive: true),
            ],
        ])
        let store = TokenStore(
            providerKinds: [.antigravity],
            usageProvider: UnavailableTokenUsageProvider(),
            accountManager: manager,
            defaults: freshDefaults())

        await store.refreshAccounts(for: .antigravity)

        XCTAssertEqual(store.accounts(for: .antigravity).map(\.id), [activeID])
        XCTAssertEqual(store.activeAccount(for: .antigravity)?.label, "primary@example.com")
        XCTAssertNil(store.accountErrorMessage(for: .antigravity))
    }

    func test_provider_account_switch_refreshes_active_account() async {
        let firstID = UUID()
        let secondID = UUID()
        let manager = InMemoryTokenAccountManager(accounts: [
            .antigravity: [
                ProviderAccount(id: firstID, provider: .antigravity, label: "Primary", isActive: true),
                ProviderAccount(id: secondID, provider: .antigravity, label: "Secondary", isActive: false),
            ],
        ])
        let store = TokenStore(
            providerKinds: [.antigravity],
            usageProvider: StaticTokenUsageProvider([ProviderUsage(provider: .antigravity, status: .available)]),
            accountManager: manager,
            defaults: freshDefaults())

        await store.setActiveAccount(secondID, for: .antigravity)

        XCTAssertEqual(store.activeAccount(for: .antigravity)?.id, secondID)
        XCTAssertEqual(store.providers.first?.status, .available)
    }

    func test_import_account_updates_catalog() async {
        let importedID = UUID()
        let manager = InMemoryTokenAccountManager(
            accounts: [:],
            importedAccount: ProviderAccount(
                id: importedID,
                provider: .antigravity,
                label: "imported@example.com",
                externalIdentifier: "imported@example.com",
                isActive: true))
        let store = TokenStore(
            providerKinds: [.antigravity],
            usageProvider: UnavailableTokenUsageProvider(),
            accountManager: manager,
            defaults: freshDefaults())

        await store.importAccount(for: .antigravity)

        XCTAssertEqual(store.activeAccount(for: .antigravity)?.id, importedID)
    }

    func test_manual_import_accounts_updates_catalog() async {
        let importedID = UUID()
        let manager = InMemoryTokenAccountManager(
            accounts: [:],
            manuallyImportedAccounts: [
                ProviderAccount(
                    id: importedID,
                    provider: .antigravity,
                    label: "manual@example.com",
                    externalIdentifier: "manual@example.com",
                    isActive: true),
            ])
        let store = TokenStore(
            providerKinds: [.antigravity],
            usageProvider: UnavailableTokenUsageProvider(),
            accountManager: manager,
            defaults: freshDefaults())

        await store.importAccounts(
            ProviderAccountImport(label: "Manual", rawValue: "refresh-token"),
            for: .antigravity)

        XCTAssertEqual(store.accounts(for: .antigravity).map(\.id), [importedID])
        XCTAssertEqual(store.activeAccount(for: .antigravity)?.label, "manual@example.com")
        XCTAssertNil(store.accountErrorMessage(for: .antigravity))
    }

    func test_provider_account_usages_mark_best_remaining_account() async {
        let lowID = UUID()
        let highID = UUID()
        let accounts = [
            ProviderAccount(id: lowID, provider: .antigravity, label: "Low", isActive: true),
            ProviderAccount(id: highID, provider: .antigravity, label: "High", isActive: false),
        ]
        let manager = InMemoryTokenAccountManager(
            accounts: [.antigravity: accounts],
            accountUsages: [
                .antigravity: [
                    ProviderAccountUsage(
                        account: accounts[0],
                        usage: ProviderUsage(
                            provider: .antigravity,
                            status: .available,
                            usageWindows: [
                                ProviderUsageWindow(
                                    id: "low",
                                    title: "Gemini Pro",
                                    kind: .model,
                                    usedPercent: 82,
                                    remainingPercent: 18),
                            ])),
                    ProviderAccountUsage(
                        account: accounts[1],
                        usage: ProviderUsage(
                            provider: .antigravity,
                            status: .available,
                            usageWindows: [
                                ProviderUsageWindow(
                                    id: "high",
                                    title: "Gemini Pro",
                                    kind: .model,
                                    usedPercent: 12,
                                    remainingPercent: 88),
                            ])),
                ],
            ])
        let store = TokenStore(
            providerKinds: [.antigravity],
            usageProvider: UnavailableTokenUsageProvider(),
            accountManager: manager,
            defaults: freshDefaults())

        await store.refreshAccountUsages(for: .antigravity)

        XCTAssertEqual(store.accountUsages(for: .antigravity).map(\.account.id), [lowID, highID])
        XCTAssertEqual(store.recommendedAccountUsage(for: .antigravity)?.account.id, highID)
        XCTAssertTrue(store.accountUsages(for: .antigravity)[1].isRecommended)
        XCTAssertFalse(store.accountUsages(for: .antigravity)[0].isRecommended)
    }

    func test_disabled_account_updates_catalog_and_recommendation_skips_it() async {
        let lowID = UUID()
        let highID = UUID()
        let accounts = [
            ProviderAccount(id: lowID, provider: .antigravity, label: "Low", isActive: true),
            ProviderAccount(id: highID, provider: .antigravity, label: "High", isActive: false),
        ]
        let manager = InMemoryTokenAccountManager(
            accounts: [.antigravity: accounts],
            accountUsages: [
                .antigravity: [
                    ProviderAccountUsage(
                        account: accounts[0],
                        usage: ProviderUsage(
                            provider: .antigravity,
                            status: .available,
                            usageWindows: [
                                ProviderUsageWindow(
                                    id: "low",
                                    title: "Gemini Pro",
                                    kind: .model,
                                    usedPercent: 82,
                                    remainingPercent: 18),
                            ])),
                    ProviderAccountUsage(
                        account: accounts[1],
                        usage: ProviderUsage(
                            provider: .antigravity,
                            status: .available,
                            usageWindows: [
                                ProviderUsageWindow(
                                    id: "high",
                                    title: "Gemini Pro",
                                    kind: .model,
                                    usedPercent: 12,
                                    remainingPercent: 88),
                            ])),
                ],
            ])
        let store = TokenStore(
            providerKinds: [.antigravity],
            usageProvider: UnavailableTokenUsageProvider(),
            accountManager: manager,
            defaults: freshDefaults())

        await store.setAccountDisabled(highID, disabled: true, reason: "403 banned", for: .antigravity)

        XCTAssertTrue(store.accounts(for: .antigravity).first(where: { $0.id == highID })?.isDisabled == true)
        XCTAssertEqual(store.recommendedAccountUsage(for: .antigravity)?.account.id, lowID)
        XCTAssertTrue(store.accountUsages(for: .antigravity)[0].isRecommended)
        XCTAssertFalse(store.accountUsages(for: .antigravity)[1].isRecommended)
    }

    func test_export_accounts_returns_payload() async {
        let firstID = UUID()
        let secondID = UUID()
        let manager = InMemoryTokenAccountManager(accounts: [
            .antigravity: [
                ProviderAccount(id: firstID, provider: .antigravity, label: "Primary", isActive: true),
                ProviderAccount(id: secondID, provider: .antigravity, label: "Secondary", isActive: false),
            ],
        ])
        let store = TokenStore(
            providerKinds: [.antigravity],
            usageProvider: UnavailableTokenUsageProvider(),
            accountManager: manager,
            defaults: freshDefaults())

        let accountExport = await store.exportAccounts([secondID], for: .antigravity)

        XCTAssertEqual(accountExport?.provider, .antigravity)
        XCTAssertEqual(accountExport?.accountCount, 1)
        XCTAssertEqual(accountExport?.fileName, "test-accounts.json")
        XCTAssertTrue(accountExport?.payload.contains("Secondary") == true)
    }
}

private final class InMemoryTokenAccountManager: TokenAccountManaging, @unchecked Sendable {
    private var accountsByProvider: [TokenProviderKind: [ProviderAccount]]
    private var accountUsagesByProvider: [TokenProviderKind: [ProviderAccountUsage]]
    private let importedAccount: ProviderAccount?
    private let manuallyImportedAccounts: [ProviderAccount]

    init(
        accounts: [TokenProviderKind: [ProviderAccount]],
        accountUsages: [TokenProviderKind: [ProviderAccountUsage]] = [:],
        importedAccount: ProviderAccount? = nil,
        manuallyImportedAccounts: [ProviderAccount] = [])
    {
        self.accountsByProvider = accounts
        self.accountUsagesByProvider = accountUsages
        self.importedAccount = importedAccount
        self.manuallyImportedAccounts = manuallyImportedAccounts
    }

    func loadAccounts(for provider: TokenProviderKind) async throws -> [ProviderAccount] {
        accountsByProvider[provider] ?? []
    }

    func loadAccountUsages(for provider: TokenProviderKind) async throws -> [ProviderAccountUsage] {
        accountUsagesByProvider[provider] ?? []
    }

    func setActiveAccount(_ accountID: UUID, for provider: TokenProviderKind) async throws {
        guard var accounts = accountsByProvider[provider],
              accounts.contains(where: { $0.id == accountID })
        else {
            throw TokenAccountManagementError.accountNotFound
        }

        accounts = accounts.map { account in
            var copy = account
            copy.isActive = account.id == accountID
            return copy
        }
        accountsByProvider[provider] = accounts
    }

    func setAccountDisabled(
        _ accountID: UUID,
        disabled: Bool,
        reason: String?,
        for provider: TokenProviderKind) async throws
    {
        guard var accounts = accountsByProvider[provider],
              let index = accounts.firstIndex(where: { $0.id == accountID })
        else {
            throw TokenAccountManagementError.accountNotFound
        }

        accounts[index].isDisabled = disabled
        accounts[index].disabledReason = disabled ? reason : nil
        if disabled, accounts[index].isActive,
           let nextIndex = accounts.firstIndex(where: { !$0.isDisabled && $0.id != accountID })
        {
            accounts[index].isActive = false
            accounts[nextIndex].isActive = true
        }
        accountsByProvider[provider] = accounts
        accountUsagesByProvider[provider] = accountUsagesByProvider[provider]?.map { usage in
            guard let account = accounts.first(where: { $0.id == usage.account.id }) else {
                return usage
            }
            var copy = usage
            copy.account = account
            copy.isRecommended = false
            return copy
        }
    }

    func deleteAccount(_ accountID: UUID, for provider: TokenProviderKind) async throws {
        guard var accounts = accountsByProvider[provider],
              accounts.contains(where: { $0.id == accountID })
        else {
            throw TokenAccountManagementError.accountNotFound
        }

        accounts.removeAll { $0.id == accountID }
        if accounts.first(where: \.isActive) == nil, !accounts.isEmpty {
            accounts[0].isActive = true
        }
        accountsByProvider[provider] = accounts
    }

    func importAccount(for provider: TokenProviderKind) async throws -> ProviderAccount? {
        guard var importedAccount else {
            throw TokenAccountManagementError.noImportableAccount(provider)
        }
        importedAccount.isActive = true
        accountsByProvider[provider] = [importedAccount]
        return importedAccount
    }

    func importAccounts(_ accountImport: ProviderAccountImport, for provider: TokenProviderKind) async throws -> [ProviderAccount] {
        guard !manuallyImportedAccounts.isEmpty else {
            throw TokenAccountManagementError.invalidImportData(provider)
        }
        accountsByProvider[provider] = manuallyImportedAccounts
        return manuallyImportedAccounts
    }

    func exportAccounts(_ accountIDs: [UUID], for provider: TokenProviderKind) async throws -> ProviderAccountExport {
        let selectedIDs = Set(accountIDs)
        let accounts = (accountsByProvider[provider] ?? []).filter { account in
            selectedIDs.isEmpty || selectedIDs.contains(account.id)
        }
        guard !accounts.isEmpty else {
            throw TokenAccountManagementError.noExportableAccount(provider)
        }
        return ProviderAccountExport(
            provider: provider,
            fileName: "test-accounts.json",
            payload: accounts.map(\.label).joined(separator: "\n"),
            accountCount: accounts.count)
    }
}
