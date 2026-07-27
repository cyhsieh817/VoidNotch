import Foundation
import Observation

@Observable
@MainActor
public final class TokenStore {
    public private(set) var selectedProviderKinds: [TokenProviderKind]
    public private(set) var providers: [ProviderUsage]
    public private(set) var isRefreshing = false
    public private(set) var lastRefreshedAt: Date?
    public private(set) var usageDisplayMode: TokenUsageDisplayMode
    public private(set) var compactDisplayProvider: TokenProviderKind?
    public private(set) var providerAccounts: [TokenProviderKind: [ProviderAccount]] = [:]
    public private(set) var providerAccountUsages: [TokenProviderKind: [ProviderAccountUsage]] = [:]
    public private(set) var accountErrorMessages: [TokenProviderKind: String] = [:]

    public let allProviderKinds = TokenProviderKind.defaultVisible
    public nonisolated static let compactRotationInterval: TimeInterval = 6

    private let usageProvider: any TokenUsageProviding
    private let accountManager: (any TokenAccountManaging)?
    private let retryPolicy: UsageRetryPolicy
    private let resilienceCache: UsageResilienceCache?
    private let dailyStore: TokenDailyStore?
    private let now: @Sendable () -> Date
    private let pollingDriver = PollingDriver()
    private var refreshReplayRequested = false
    private var refreshReplayForced = false
    private var retryStates: [TokenProviderKind: UsageRetryState] = [:]
    private let defaults: UserDefaults
    private let defaultsKey = "TokenStore.selectedProviderKinds"
    private let displayModeDefaultsKey = "TokenStore.usageDisplayMode"
    private let compactDisplayProviderDefaultsKey = "TokenStore.compactDisplayProviderKind"

    public init(
        providerKinds: [TokenProviderKind]? = nil,
        usageDisplayMode: TokenUsageDisplayMode? = nil,
        usageProvider: any TokenUsageProviding = UnavailableTokenUsageProvider(),
        accountManager: (any TokenAccountManaging)? = nil,
        defaults: UserDefaults = .standard,
        retryPolicy: UsageRetryPolicy = .init(),
        resilienceCache: UsageResilienceCache? = nil,
        dailyStore: TokenDailyStore? = nil,
        now: @escaping @Sendable () -> Date = { Date() })
    {
        let initialProviderKinds = providerKinds ?? Self.loadProviderKinds(from: defaults)
        self.defaults = defaults
        self.usageProvider = usageProvider
        self.accountManager = accountManager
        self.retryPolicy = retryPolicy
        self.resilienceCache = resilienceCache
        self.dailyStore = dailyStore
        self.now = now
        self.selectedProviderKinds = initialProviderKinds
        self.providers = initialProviderKinds.map(ProviderUsage.placeholder)
        self.usageDisplayMode = usageDisplayMode ?? Self.loadUsageDisplayMode(from: defaults)
        self.compactDisplayProvider = Self.loadCompactDisplayProvider(from: defaults, enabledProviders: initialProviderKinds)
    }

    public convenience init(
        providers: [ProviderUsage],
        defaults: UserDefaults = .standard,
        retryPolicy: UsageRetryPolicy = .init(),
        resilienceCache: UsageResilienceCache? = nil,
        dailyStore: TokenDailyStore? = nil,
        now: @escaping @Sendable () -> Date = { Date() })
    {
        self.init(
            providerKinds: providers.map(\.provider),
            usageProvider: StaticTokenUsageProvider(providers),
            defaults: defaults,
            retryPolicy: retryPolicy,
            resilienceCache: resilienceCache,
            dailyStore: dailyStore,
            now: now)
        self.providers = providers
    }

    public var availableProviderCount: Int { providers.filter { $0.status == .available }.count }
    public var attentionProviderCount: Int {
        providers.filter {
            $0.status.isAttentionState
                || $0.errorMessage != nil
                || !$0.freshness.isFresh
                || $0.diagnosis != nil
        }.count
    }
    public var enabledProviderCount: Int { selectedProviderKinds.count }
    public var providerHealthSummary: String {
        "\(availableProviderCount)/\(enabledProviderCount) available"
    }

    public func retryState(for provider: TokenProviderKind) -> UsageRetryState {
        retryStates[provider] ?? UsageRetryState()
    }

    public func isProviderEnabled(_ provider: TokenProviderKind) -> Bool {
        selectedProviderKinds.contains(provider)
    }

    public func canDisableProvider(_ provider: TokenProviderKind) -> Bool {
        selectedProviderKinds.count > 1 || !selectedProviderKinds.contains(provider)
    }

    public func setProvider(_ provider: TokenProviderKind, enabled: Bool) {
        if enabled {
            guard !selectedProviderKinds.contains(provider) else { return }
            let next = selectedProviderKinds + [provider]
            selectedProviderKinds = orderedProviders(next)
        } else {
            guard canDisableProvider(provider) else { return }
            selectedProviderKinds.removeAll { $0 == provider }
            if compactDisplayProvider == provider {
                compactDisplayProvider = nil
                saveCompactDisplayProvider()
            }
        }

        saveProviderKinds()
        providers = ordered(providers, matching: selectedProviderKinds)
        Task { await refresh() }
    }

    public func setUsageDisplayMode(_ mode: TokenUsageDisplayMode) {
        guard usageDisplayMode != mode else { return }
        usageDisplayMode = mode
        defaults.set(mode.rawValue, forKey: displayModeDefaultsKey)
    }

    public func setCompactDisplayProvider(_ provider: TokenProviderKind?) {
        let next = provider.flatMap { selectedProviderKinds.contains($0) ? $0 : nil }
        guard compactDisplayProvider != next else { return }
        compactDisplayProvider = next
        saveCompactDisplayProvider()
    }

    public func compactDisplayUsage(at date: Date = Date()) -> ProviderUsage? {
        if let compactDisplayProvider,
           selectedProviderKinds.contains(compactDisplayProvider)
        {
            return providers.first(where: { $0.provider == compactDisplayProvider })
                ?? ProviderUsage.placeholder(for: compactDisplayProvider)
        }

        guard !providers.isEmpty else {
            return selectedProviderKinds.first.map(ProviderUsage.placeholder)
        }
        let slot = Int(max(0, date.timeIntervalSinceReferenceDate) / Self.compactRotationInterval) % providers.count
        return providers[slot]
    }

    public func accounts(for provider: TokenProviderKind) -> [ProviderAccount] {
        providerAccounts[provider] ?? []
    }

    public func activeAccount(for provider: TokenProviderKind) -> ProviderAccount? {
        accounts(for: provider).first(where: \.isActive)
    }

    public func accountUsages(for provider: TokenProviderKind) -> [ProviderAccountUsage] {
        providerAccountUsages[provider] ?? []
    }

    public func recommendedAccountUsage(for provider: TokenProviderKind) -> ProviderAccountUsage? {
        let usages = accountUsages(for: provider)
        if let recommended = usages.first(where: \.isRecommended) {
            return recommended
        }
        let scored = usages.compactMap { usage -> (usage: ProviderAccountUsage, score: Int)? in
            guard let score = usage.recommendationScore else { return nil }
            return (usage, score)
        }
        return scored.max(by: { $0.score < $1.score })?.usage
    }

    public func accountErrorMessage(for provider: TokenProviderKind) -> String? {
        accountErrorMessages[provider]
    }

    /// Daily cost/token series for heatmap views.
    /// Returns an empty array when no daily store is configured.
    public func dailySeries(
        days: Int,
        endingAt: Date,
        provider: TokenProviderKind? = nil) -> [TokenDailyRecord]
    {
        guard let dailyStore else { return [] }
        return dailyStore.series(provider: provider?.rawValue, days: days, endingAt: endingAt)
    }

    public func refreshAccounts(for provider: TokenProviderKind) async {
        guard let accountManager else {
            providerAccounts[provider] = []
            accountErrorMessages[provider] = nil
            return
        }

        do {
            providerAccounts[provider] = try await accountManager.loadAccounts(for: provider)
            accountErrorMessages[provider] = nil
        } catch let error as TokenAccountManagementError {
            if case .unsupportedProvider = error {
                providerAccounts[provider] = []
                providerAccountUsages[provider] = []
                accountErrorMessages[provider] = nil
            } else {
                accountErrorMessages[provider] = error.localizedDescription
            }
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
        }
    }

    public func refreshAccountUsages(for provider: TokenProviderKind) async {
        guard let accountManager else {
            providerAccountUsages[provider] = []
            accountErrorMessages[provider] = nil
            return
        }

        do {
            providerAccountUsages[provider] = markedRecommended(try await accountManager.loadAccountUsages(for: provider))
            accountErrorMessages[provider] = nil
        } catch let error as TokenAccountManagementError {
            if case .unsupportedProvider = error {
                providerAccountUsages[provider] = []
            } else {
                accountErrorMessages[provider] = error.localizedDescription
            }
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
        }
    }

    public func refreshAccountCatalog() async {
        for provider in allProviderKinds {
            await refreshAccounts(for: provider)
            await refreshAccountUsages(for: provider)
        }
    }

    public func setActiveAccount(_ accountID: UUID, for provider: TokenProviderKind) async {
        guard let accountManager else { return }

        do {
            try await accountManager.setActiveAccount(accountID, for: provider)
            await refreshAccounts(for: provider)
            await refreshAccountUsages(for: provider)
            await refresh()
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
        }
    }

    public func setAccountDisabled(
        _ accountID: UUID,
        disabled: Bool,
        reason: String? = nil,
        for provider: TokenProviderKind) async
    {
        guard let accountManager else { return }

        do {
            try await accountManager.setAccountDisabled(accountID, disabled: disabled, reason: reason, for: provider)
            await refreshAccounts(for: provider)
            await refreshAccountUsages(for: provider)
            await refresh()
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
        }
    }

    public func importAccount(for provider: TokenProviderKind) async {
        guard let accountManager else { return }

        do {
            _ = try await accountManager.importAccount(for: provider)
            await refreshAccounts(for: provider)
            await refreshAccountUsages(for: provider)
            await refresh()
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
        }
    }

    public func importAccounts(_ accountImport: ProviderAccountImport, for provider: TokenProviderKind) async {
        guard let accountManager else { return }

        do {
            _ = try await accountManager.importAccounts(accountImport, for: provider)
            await refreshAccounts(for: provider)
            await refreshAccountUsages(for: provider)
            await refresh()
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
        }
    }

    public func exportAccounts(_ accountIDs: [UUID], for provider: TokenProviderKind) async -> ProviderAccountExport? {
        guard let accountManager else { return nil }

        do {
            let accountExport = try await accountManager.exportAccounts(accountIDs, for: provider)
            accountErrorMessages[provider] = nil
            return accountExport
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func applyAccountToAgyCLI(_ accountID: UUID, for provider: TokenProviderKind) async -> Bool {
        guard let accountManager else { return false }

        do {
            try await accountManager.applyAccountToAgyCLI(accountID, for: provider)
            accountErrorMessages[provider] = nil
            return true
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
            return false
        }
    }

    public func deleteAccount(_ accountID: UUID, for provider: TokenProviderKind) async {
        guard let accountManager else { return }

        do {
            try await accountManager.deleteAccount(accountID, for: provider)
            await refreshAccounts(for: provider)
            await refreshAccountUsages(for: provider)
            await refresh()
        } catch {
            accountErrorMessages[provider] = error.localizedDescription
        }
    }

    public func refresh(forced: Bool = false) async {
        if isRefreshing {
            refreshReplayRequested = true
            refreshReplayForced = refreshReplayForced || forced
            return
        }

        // Consume the caller's forced flag once; later replay rounds only honor
        // forced when a concurrent refresh(forced: true) arrived during isRefreshing.
        var pendingForced = forced
        repeat {
            let roundForced = pendingForced || refreshReplayForced
            pendingForced = false
            refreshReplayRequested = false
            refreshReplayForced = false
            isRefreshing = true

            let refreshDate = now()
            let providerKinds = selectedProviderKinds
            let attemptedProviders = providerKinds.filter { provider in
                retryPolicy.shouldAttempt(
                    retryState(for: provider),
                    now: refreshDate,
                    forced: roundForced)
            }

            // Snapshot so attempted providers with no result can leave .refreshing.
            let providersBeforeRefreshing = providers
            providers = providers.map { current in
                guard attemptedProviders.contains(current.provider) else { return current }
                var copy = current
                copy.status = .refreshing
                return copy
            }

            let results: [ProviderUsageFetchResult]
            if attemptedProviders.isEmpty {
                results = []
            } else {
                results = await usageProvider.fetchUsage(for: attemptedProviders)
            }

            var resultByProvider: [TokenProviderKind: ProviderUsage] = [:]
            for result in results {
                var usage = result.usage
                if let diagnosis = result.diagnosis {
                    if let resilienceCache {
                        usage = resilienceCache.recover(
                            failed: usage,
                            diagnosis: diagnosis,
                            now: refreshDate)
                    } else {
                        usage.freshness = .fresh
                        usage.diagnosis = diagnosis
                    }
                    retryStates[usage.provider] = retryPolicy.advanced(
                        retryState(for: usage.provider),
                        after: diagnosis,
                        now: refreshDate)
                } else {
                    usage.freshness = .fresh
                    usage.diagnosis = nil
                    // Only real successes become last-known-good; diagnosis-nil
                    // non-available snapshots must not pollute the cache.
                    if usage.status == .available {
                        resilienceCache?.recordSuccess(usage, at: refreshDate)
                    }
                    retryStates[usage.provider] = retryPolicy.recovered(from: retryState(for: usage.provider))
                }
                resultByProvider[usage.provider] = usage
            }

            let preRefreshByProvider = Dictionary(
                uniqueKeysWithValues: providersBeforeRefreshing.map { ($0.provider, $0) })
            providers = providers.map { current in
                if let updated = resultByProvider[current.provider] {
                    return updated
                }
                if attemptedProviders.contains(current.provider),
                   let previous = preRefreshByProvider[current.provider]
                {
                    return previous
                }
                return current
            }
            providers = ordered(providers, matching: selectedProviderKinds)

            if !attemptedProviders.isEmpty {
                lastRefreshedAt = refreshDate
            }

            let dailyHistory = results.flatMap { $0.dailyHistory }
            if let dailyStore, !dailyHistory.isEmpty {
                do {
                    _ = try dailyStore.ingest(dailyHistory, now: refreshDate)
                } catch {
                    NSLog("TokenDailyStore ingest failed: %@", error.localizedDescription)
                }
            }
            if let resilienceCache {
                do {
                    try resilienceCache.persist()
                } catch {
                    NSLog("UsageResilienceCache persist failed: %@", error.localizedDescription)
                }
            }

            isRefreshing = false
        } while refreshReplayRequested
    }

    public func startPolling(interval: TimeInterval = 300) {
        pollingDriver.start(interval: interval) { [weak self] in
            await self?.refresh()
        }
    }

    public func stopPolling() {
        pollingDriver.stop()
    }

    private func ordered(_ snapshots: [ProviderUsage], matching providers: [TokenProviderKind]) -> [ProviderUsage] {
        let byProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        return providers.map { byProvider[$0] ?? ProviderUsage.placeholder(for: $0) }
    }

    private func orderedProviders(_ providers: [TokenProviderKind]) -> [TokenProviderKind] {
        TokenProviderKind.defaultVisible.filter { providers.contains($0) }
    }

    private func markedRecommended(_ usages: [ProviderAccountUsage]) -> [ProviderAccountUsage] {
        var result = usages.map { usage in
            var copy = usage
            copy.isRecommended = false
            return copy
        }
        guard let bestIndex = result.indices.max(by: { lhs, rhs in
            (result[lhs].recommendationScore ?? -1) < (result[rhs].recommendationScore ?? -1)
        }),
            result[bestIndex].recommendationScore != nil
        else {
            return result
        }
        result[bestIndex].isRecommended = true
        return result
    }

    private func saveProviderKinds() {
        defaults.set(selectedProviderKinds.map(\.rawValue), forKey: defaultsKey)
    }

    private func saveCompactDisplayProvider() {
        if let compactDisplayProvider {
            defaults.set(compactDisplayProvider.rawValue, forKey: compactDisplayProviderDefaultsKey)
        } else {
            defaults.removeObject(forKey: compactDisplayProviderDefaultsKey)
        }
    }

    private static func loadProviderKinds(from defaults: UserDefaults) -> [TokenProviderKind] {
        guard let rawValues = defaults.array(forKey: "TokenStore.selectedProviderKinds") as? [String] else {
            return TokenProviderKind.defaultVisible
        }

        let providers = rawValues.compactMap(TokenProviderKind.init(rawValue:))
        return providers.isEmpty ? TokenProviderKind.defaultVisible : TokenProviderKind.defaultVisible.filter { providers.contains($0) }
    }

    private static func loadUsageDisplayMode(from defaults: UserDefaults) -> TokenUsageDisplayMode {
        guard let rawValue = defaults.string(forKey: "TokenStore.usageDisplayMode"),
              let mode = TokenUsageDisplayMode(rawValue: rawValue)
        else {
            return .remaining
        }
        return mode
    }

    private static func loadCompactDisplayProvider(
        from defaults: UserDefaults,
        enabledProviders: [TokenProviderKind]) -> TokenProviderKind?
    {
        guard let rawValue = defaults.string(forKey: "TokenStore.compactDisplayProviderKind"),
              let provider = TokenProviderKind(rawValue: rawValue),
              enabledProviders.contains(provider)
        else {
            return nil
        }
        return provider
    }
}
