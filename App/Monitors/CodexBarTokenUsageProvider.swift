//
//  CodexBarTokenUsageProvider.swift — CodexBarCore adapter
//
//  把 CodexBarCore 的 cost / quota snapshot 映射成 VoidNotch 自己的 ProviderUsage。
//  unsupported provider 會保留在 UI 狀態列，避免誤顯示成 0 用量。
//

import Foundation
import OSLog
import VoidNotchKit

#if canImport(CodexBarCore)
import CodexBarCore

public struct CodexBarTokenUsageProvider: TokenUsageProviding {
    private static let log = Logger(subsystem: "dev.voidnotch", category: "token-provider")

    private let fetcher: CostUsageFetcher
    private let historyDays: Int
    private let tokenAccountStore: any ProviderTokenAccountStoring

    public init(
        fetcher: CostUsageFetcher = CostUsageFetcher(),
        historyDays: Int = 30,
        tokenAccountStore: any ProviderTokenAccountStoring = FileTokenAccountStore())
    {
        Self.configureKeychainPolicy()
        self.fetcher = fetcher
        self.historyDays = max(1, min(365, historyDays))
        self.tokenAccountStore = tokenAccountStore
    }

    private static func configureKeychainPolicy() {
        KeychainAccessGate.forceDisabledForProcess(
            reason: "VoidNotch uses non-interactive provider snapshots and must not present CodexBar-branded keychain prompts.")
    }

    public func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsage] {
        // 各 provider 含 cost snapshot + live fetch(web timeout 可達 12s);序列 await 會把延遲疊加。
        // 改並行,延遲降到最慢單一 provider;回傳順序仍對齊輸入。
        let startedAt = Date()
        let usage = await mapConcurrentlyPreservingOrder(providers) { provider in
            await fetchProviderUsage(provider)
        }
        Self.log.debug("Token refresh completed providers=\(providers.count, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public)")
        return usage
    }

    private func fetchProviderUsage(_ provider: TokenProviderKind) async -> ProviderUsage {
        let startedAt = Date()
        var liveUsage: ProviderUsage?
        var liveError: Error?

        if provider.supportsLiveUsageSnapshot {
            let liveStartedAt = Date()
            do {
                liveUsage = try await fetchLiveUsage(provider)
                Self.log.debug("Token live fetch succeeded provider=\(provider.id, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: liveStartedAt), privacy: .public)")
            } catch {
                liveError = error
                Self.log.debug("Token live fetch failed provider=\(provider.id, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: liveStartedAt), privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            }
        }

        if provider.supportsCostSnapshot {
            guard let codexBarProvider = provider.codexBarProvider else {
                return Self.profiled(Self.unsupportedUsage(for: provider), provider: provider, startedAt: startedAt)
            }

            let costStartedAt = Date()
            do {
                let snapshot = try await fetcher.loadTokenSnapshot(
                    provider: codexBarProvider,
                    forceRefresh: false,
                    allowVertexClaudeFallback: false,
                    historyDays: historyDays,
                    refreshPricingInBackground: true)
                Self.log.debug("Token cost fetch succeeded provider=\(provider.id, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: costStartedAt), privacy: .public)")
                let costUsage = Self.map(snapshot, provider: provider)
                if var liveUsage {
                    liveUsage.sessionTokens = costUsage.sessionTokens
                    liveUsage.last30DaysTokens = costUsage.last30DaysTokens
                    liveUsage.sessionCostUSD = costUsage.sessionCostUSD
                    liveUsage.last30DaysCostUSD = costUsage.last30DaysCostUSD
                    liveUsage.currencyCode = costUsage.currencyCode
                    liveUsage.errorMessage = liveUsage.errorMessage ?? costUsage.errorMessage
                    return Self.profiled(liveUsage, provider: provider, startedAt: startedAt)
                }
                return Self.profiled(costUsage, provider: provider, startedAt: startedAt)
            } catch {
                Self.log.debug("Token cost fetch failed provider=\(provider.id, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: costStartedAt), privacy: .public) error=\(error.localizedDescription, privacy: .private)")
                if let liveUsage {
                    return Self.profiled(liveUsage, provider: provider, startedAt: startedAt)
                }
                return Self.profiled(Self.map(error, provider: provider), provider: provider, startedAt: startedAt)
            }
        }

        if let liveUsage {
            return Self.profiled(liveUsage, provider: provider, startedAt: startedAt)
        }

        if let liveError {
            return Self.profiled(Self.map(liveError, provider: provider), provider: provider, startedAt: startedAt)
        }

        return Self.profiled(ProviderUsage(
            provider: provider,
            status: .unsupported,
            errorMessage: "\(provider.displayName) usage adapter is pending"),
            provider: provider,
            startedAt: startedAt)
    }

    private static func profiled(
        _ usage: ProviderUsage,
        provider: TokenProviderKind,
        startedAt: Date) -> ProviderUsage
    {
        log.debug("Token provider fetch completed provider=\(provider.id, privacy: .public) status=\(usage.status.rawValue, privacy: .public) duration_ms=\(elapsedMilliseconds(since: startedAt), privacy: .public)")
        return usage
    }

    private static func elapsedMilliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1_000).rounded())
    }

    func fetchUsage(
        for provider: TokenProviderKind,
        selectedAccount: ProviderTokenAccount) async throws -> ProviderUsage
    {
        try await fetchLiveUsage(provider, accountOverride: selectedAccount)
    }

    private func fetchLiveUsage(
        _ provider: TokenProviderKind,
        accountOverride: ProviderTokenAccount? = nil) async throws -> ProviderUsage
    {
        guard let codexProvider = provider.codexBarProvider else {
            return Self.unsupportedUsage(for: provider)
        }

        let descriptor = ProviderDescriptorRegistry.descriptor(for: codexProvider)
        let browserDetection = BrowserDetection()
        let context = makeFetchContext(
            provider: codexProvider,
            accountOverride: accountOverride,
            browserDetection: browserDetection)
        let result = try await descriptor.fetch(context: context)
        return Self.mapLive(
            result,
            descriptor: descriptor,
            provider: provider,
            version: descriptor.cli.versionDetector?(browserDetection))
    }

    private func makeFetchContext(
        provider: UsageProvider,
        accountOverride: ProviderTokenAccount? = nil,
        browserDetection: BrowserDetection) -> ProviderFetchContext
    {
        let selectedAccount = accountOverride ?? Self.selectedTokenAccount(for: provider, store: tokenAccountStore)
        var env = ProcessInfo.processInfo.environment
        if let selectedAccount {
            TokenAccountSupportCatalog.scrubEnvironmentForSelectedAccount(
                &env,
                provider: provider,
                token: selectedAccount.token)
            if let override = TokenAccountSupportCatalog.envOverride(for: provider, token: selectedAccount.token) {
                env.merge(override) { _, new in new }
            }
        }

        return ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: true,
            includeOptionalUsage: true,
            webTimeout: 12,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: Self.defaultProviderSettings(),
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: ClaudeUsageFetcher(
                browserDetection: browserDetection,
                environment: env,
                runtime: .app,
                dataSource: .oauth,
                useWebExtras: false),
            browserDetection: browserDetection,
            selectedTokenAccountID: selectedAccount?.id,
            tokenAccountTokenUpdater: Self.tokenUpdater(for: selectedAccount, store: tokenAccountStore),
            costUsageHistoryDays: historyDays,
            persistsCLISessions: true,
            persistentCLISessionIdleWindow: 600)
    }

    private static func defaultProviderSettings() -> ProviderSettingsSnapshot {
        ProviderSettingsSnapshot.make(
            debugKeepCLISessionsAlive: true,
            codex: ProviderSettingsSnapshot.CodexProviderSettings(
                usageDataSource: .auto,
                cookieSource: .auto,
                manualCookieHeader: nil),
            claude: ProviderSettingsSnapshot.ClaudeProviderSettings(
                usageDataSource: .auto,
                webExtrasEnabled: false,
                cookieSource: .auto,
                manualCookieHeader: nil),
            cursor: ProviderSettingsSnapshot.CursorProviderSettings(
                cookieSource: .auto,
                manualCookieHeader: nil),
            copilot: ProviderSettingsSnapshot.CopilotProviderSettings())
    }

    private static func map(_ snapshot: CostUsageTokenSnapshot, provider: TokenProviderKind) -> ProviderUsage {
        let hasData = snapshot.sessionTokens != nil || snapshot.last30DaysTokens != nil || !snapshot.daily.isEmpty
        return ProviderUsage(
            provider: provider,
            status: hasData ? .available : .unavailable,
            usedPercent: ProviderUsage.percentage(
                sessionTokens: snapshot.sessionTokens,
                totalTokens: snapshot.last30DaysTokens),
            sessionTokens: snapshot.sessionTokens,
            last30DaysTokens: snapshot.last30DaysTokens,
            sessionCostUSD: snapshot.sessionCostUSD,
            last30DaysCostUSD: snapshot.last30DaysCostUSD,
            currencyCode: snapshot.currencyCode,
            updatedAt: snapshot.updatedAt,
            errorMessage: hasData ? nil : "No local token records yet")
    }

    private static func mapLive(
        _ result: ProviderFetchResult,
        descriptor: ProviderDescriptor,
        provider: TokenProviderKind,
        version: String?) -> ProviderUsage
    {
        let snapshot = result.usage
        let windows = usageWindows(from: snapshot, metadata: descriptor.metadata)
        let primaryWindow = windows.first(where: \.usageKnown) ?? windows.first
        let hasData = primaryWindow != nil || snapshot.identity(for: descriptor.id) != nil

        return ProviderUsage(
            provider: provider,
            status: hasData ? .available : .unavailable,
            usedPercent: primaryWindow?.usedPercent ?? 0,
            updatedAt: snapshot.updatedAt,
            errorMessage: hasData ? nil : "No live usage data returned",
            detailText: liveDetailText(primaryWindow: primaryWindow, sourceLabel: result.sourceLabel),
            usageWindows: windows,
            sourceLabel: result.sourceLabel,
            strategyID: result.strategyID,
            accountEmail: snapshot.identity(for: descriptor.id)?.accountEmail,
            accountPlan: snapshot.identity(for: descriptor.id)?.loginMethod,
            cliVersion: version)
    }

    private static func usageWindows(
        from snapshot: UsageSnapshot,
        metadata: ProviderMetadata) -> [ProviderUsageWindow]
    {
        var windows: [ProviderUsageWindow] = []
        if let primary = snapshot.primary {
            // Grok: CodexBar 依 billing period 動態標成 Weekly/Monthly，否則回落 Credits。
            let primaryTitle: String
            if metadata.id == .grok {
                primaryTitle = GrokProviderDescriptor.primaryLabel(window: primary) ?? metadata.sessionLabel
            } else {
                primaryTitle = metadata.sessionLabel
            }
            windows.append(
                usageWindow(
                    id: "\(metadata.id.rawValue)-primary",
                    title: primaryTitle,
                    rateWindow: primary,
                    usageKnown: true))
        }
        if let secondary = snapshot.secondary {
            windows.append(
                usageWindow(
                    id: "\(metadata.id.rawValue)-secondary",
                    title: metadata.weeklyLabel,
                    rateWindow: secondary,
                    usageKnown: true))
        }
        if let tertiary = snapshot.tertiary {
            windows.append(
                usageWindow(
                    id: "\(metadata.id.rawValue)-tertiary",
                    title: metadata.opusLabel ?? "Additional",
                    rateWindow: tertiary,
                    usageKnown: true))
        }
        if let extraRateWindows = snapshot.extraRateWindows {
            windows.append(contentsOf: extraRateWindows.map {
                usageWindow(
                    id: $0.id,
                    title: $0.title,
                    rateWindow: $0.window,
                    usageKnown: $0.usageKnown)
            })
        }
        return deduplicatedWindows(windows)
    }

    private static func usageWindow(
        id: String,
        title: String,
        rateWindow: RateWindow,
        usageKnown: Bool) -> ProviderUsageWindow
    {
        ProviderUsageWindow(
            id: id,
            title: title,
            kind: classifyWindow(title: title, windowMinutes: rateWindow.windowMinutes),
            usedPercent: clampedPercent(rateWindow.usedPercent),
            remainingPercent: clampedPercent(rateWindow.remainingPercent),
            windowMinutes: rateWindow.windowMinutes,
            resetsAt: rateWindow.resetsAt,
            resetDescription: rateWindow.resetDescription,
            usageKnown: usageKnown)
    }

    private static func deduplicatedWindows(_ windows: [ProviderUsageWindow]) -> [ProviderUsageWindow] {
        var seen: Set<String> = []
        var result: [ProviderUsageWindow] = []
        for window in windows {
            let key = "\(window.title.lowercased())-\(window.windowMinutes ?? -1)-\(window.usedPercent)-\(window.remainingPercent)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(window)
        }
        return result
    }

    private static func liveDetailText(primaryWindow: ProviderUsageWindow?, sourceLabel: String) -> String? {
        guard let primaryWindow else { return sourceLabel }
        return "\(primaryWindow.title) remaining \(primaryWindow.remainingPercent)% · \(sourceLabel)"
    }

    private static func classifyWindow(title: String, windowMinutes: Int?) -> ProviderUsageWindowKind {
        switch windowMinutes {
        case 300:
            return .fiveHour
        case 10080:
            return .weekly
        case 43200, 43800, 44640:
            return .monthly
        default:
            break
        }

        let normalized = title.lowercased()
        if normalized.contains("5h") || normalized.contains("5-hour") || normalized.contains("five hour") {
            return .fiveHour
        }
        if normalized.contains("weekly") || normalized.contains("week") {
            return .weekly
        }
        if normalized.contains("monthly") || normalized.contains("month") {
            return .monthly
        }
        // Grok SuperGrok credits cycle often surfaces as "Credits".
        if normalized.contains("credit") {
            return .monthly
        }
        if normalized.contains("gemini") || normalized.contains("claude") || normalized.contains("gpt") {
            return .model
        }
        return .other
    }

    private static func clampedPercent(_ value: Double) -> Int {
        min(100, max(0, Int(value.rounded())))
    }

    private static func map(_ error: Error, provider: TokenProviderKind) -> ProviderUsage {
        let status: ProviderUsageStatus
        if case CostUsageError.unsupportedProvider = error {
            status = .unsupported
        } else {
            status = .unavailable
        }

        return ProviderUsage(
            provider: provider,
            status: status,
            errorMessage: error.localizedDescription)
    }

    private static func unsupportedUsage(for provider: TokenProviderKind) -> ProviderUsage {
        ProviderUsage(
            provider: provider,
            status: .unsupported,
            errorMessage: "\(provider.displayName) usage adapter is pending")
    }

    private static func selectedTokenAccount(
        for provider: UsageProvider,
        store: any ProviderTokenAccountStoring) -> ProviderTokenAccount?
    {
        guard TokenAccountSupportCatalog.support(for: provider) != nil,
              let data = try? store.loadAccounts()[provider],
              !data.accounts.isEmpty
        else {
            return nil
        }
        let metadata = (try? ProviderTokenAccountMetadataStore().loadMetadata(for: provider)) ?? [:]
        let activeIndex = data.clampedActiveIndex()
        if metadata[data.accounts[activeIndex].id.uuidString]?.isDisabled != true {
            return data.accounts[activeIndex]
        }
        let orderedIndices = Array(activeIndex..<data.accounts.count) + Array(0..<activeIndex)
        guard let nextIndex = orderedIndices.first(where: { index in
            metadata[data.accounts[index].id.uuidString]?.isDisabled != true
        }) else {
            return nil
        }
        return data.accounts[nextIndex]
    }

    private static func tokenUpdater(
        for account: ProviderTokenAccount?,
        store: any ProviderTokenAccountStoring) -> ProviderFetchContext.TokenAccountTokenUpdater?
    {
        guard let account else { return nil }
        return { provider, accountID, token in
            guard accountID == account.id else { return }
            do {
                try Self.updateStoredTokenAccount(
                    provider: provider,
                    accountID: accountID,
                    token: token,
                    store: store)
            } catch {
                Self.log.debug("Token account update failed provider=\(provider.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private static func updateStoredTokenAccount(
        provider: UsageProvider,
        accountID: UUID,
        token: String,
        store: any ProviderTokenAccountStoring) throws
    {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var accountsByProvider = try store.loadAccounts()
        guard let data = accountsByProvider[provider],
              let index = data.accounts.firstIndex(where: { $0.id == accountID })
        else {
            return
        }

        let existing = data.accounts[index]
        var accounts = data.accounts
        accounts[index] = ProviderTokenAccount(
            id: existing.id,
            label: existing.label,
            token: trimmed,
            addedAt: existing.addedAt,
            lastUsed: Date().timeIntervalSince1970,
            externalIdentifier: existing.externalIdentifier,
            organizationID: existing.organizationID)
        accountsByProvider[provider] = ProviderTokenAccountData(
            version: data.version,
            accounts: accounts,
            activeIndex: data.clampedActiveIndex())
        try store.storeAccounts(accountsByProvider)
    }
}

private extension TokenProviderKind {
    var codexBarProvider: UsageProvider? {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        case .openAI: return .openai
        case .gemini: return .gemini
        case .antigravity: return .antigravity
        case .copilot: return .copilot
        case .cursor: return .cursor
        case .grok: return .grok
        case .vertexAI: return .vertexai
        case .bedrock: return .bedrock
        }
    }
}
#else
public struct CodexBarTokenUsageProvider: TokenUsageProviding {
    public init() {}

    public func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsage] {
        providers.map {
            ProviderUsage(
                provider: $0,
                status: .unavailable,
                errorMessage: "Token usage adapter is not linked to the app target")
        }
    }
}
#endif
