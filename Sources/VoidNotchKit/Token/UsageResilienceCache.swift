import Foundation

public final class UsageResilienceCache: @unchecked Sendable {
    public static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoidNotch/token-usage-cache.json")
    }

    private struct CachedUsage: Codable {
        let usedPercent: Int
        let sessionTokens: Int?
        let last30DaysTokens: Int?
        let sessionCostUSD: Double?
        let last30DaysCostUSD: Double?
        let currencyCode: String
        let detailText: String?
        let usageWindows: [ProviderUsageWindow]
        let sourceLabel: String?
        let strategyID: String?
        let accountEmail: String?
        let accountPlan: String?
        let cliVersion: String?
        let updatedAt: Date?
        let succeededAt: Date

        init(usage: ProviderUsage, succeededAt: Date) {
            self.usedPercent = usage.usedPercent
            self.sessionTokens = usage.sessionTokens
            self.last30DaysTokens = usage.last30DaysTokens
            self.sessionCostUSD = usage.sessionCostUSD
            self.last30DaysCostUSD = usage.last30DaysCostUSD
            self.currencyCode = usage.currencyCode
            self.detailText = usage.detailText
            self.usageWindows = usage.usageWindows
            self.sourceLabel = usage.sourceLabel
            self.strategyID = usage.strategyID
            self.accountEmail = usage.accountEmail
            self.accountPlan = usage.accountPlan
            self.cliVersion = usage.cliVersion
            self.updatedAt = usage.updatedAt
            self.succeededAt = succeededAt
        }

        func usage(for provider: TokenProviderKind) -> ProviderUsage {
            ProviderUsage(
                provider: provider,
                status: .available,
                usedPercent: usedPercent,
                sessionTokens: sessionTokens,
                last30DaysTokens: last30DaysTokens,
                sessionCostUSD: sessionCostUSD,
                last30DaysCostUSD: last30DaysCostUSD,
                currencyCode: currencyCode,
                updatedAt: updatedAt,
                detailText: detailText,
                usageWindows: usageWindows,
                sourceLabel: sourceLabel,
                strategyID: strategyID,
                accountEmail: accountEmail,
                accountPlan: accountPlan,
                cliVersion: cliVersion)
        }
    }

    private struct Archive: Codable {
        let version: Int
        let entries: [String: CachedUsage]

        init(entries: [String: CachedUsage]) {
            self.version = 1
            self.entries = entries
        }
    }

    private let fileURL: URL
    private var entries: [String: CachedUsage] = [:]
    private let fileManager = FileManager.default

    public init(fileURL: URL = UsageResilienceCache.defaultFileURL()) {
        self.fileURL = fileURL
        reload()
    }

    public func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == 1
        else {
            entries = [:]
            return
        }
        entries = archive.entries
    }

    public func lastKnownGood(for provider: TokenProviderKind) -> (usage: ProviderUsage, succeededAt: Date)? {
        guard let entry = entries[provider.rawValue] else { return nil }
        return (entry.usage(for: provider), entry.succeededAt)
    }

    public func recordSuccess(_ usage: ProviderUsage, at now: Date) {
        entries[usage.provider.rawValue] = CachedUsage(usage: usage, succeededAt: now)
    }

    public func recover(
        failed: ProviderUsage,
        diagnosis: UsageFetchDiagnosis,
        now: Date) -> ProviderUsage
    {
        guard let cached = entries[failed.provider.rawValue] else {
            var recovered = failed
            recovered.freshness = .fresh
            recovered.diagnosis = diagnosis
            return recovered
        }

        let cachedUsage = cached.usage(for: failed.provider)
        var recovered = failed
        let isCompleteFailure = failed.usageWindows.isEmpty
            && failed.sessionTokens == nil
            && failed.last30DaysTokens == nil
            && failed.sessionCostUSD == nil
            && failed.last30DaysCostUSD == nil

        if isCompleteFailure {
            recovered.usedPercent = cachedUsage.usedPercent
            recovered.sessionTokens = cachedUsage.sessionTokens
            recovered.last30DaysTokens = cachedUsage.last30DaysTokens
            recovered.sessionCostUSD = cachedUsage.sessionCostUSD
            recovered.last30DaysCostUSD = cachedUsage.last30DaysCostUSD
            recovered.currencyCode = cachedUsage.currencyCode
            recovered.detailText = cachedUsage.detailText
            recovered.usageWindows = cachedUsage.usageWindows
            recovered.sourceLabel = cachedUsage.sourceLabel
            recovered.strategyID = cachedUsage.strategyID
            recovered.accountEmail = cachedUsage.accountEmail
            recovered.accountPlan = cachedUsage.accountPlan
            recovered.cliVersion = cachedUsage.cliVersion
            recovered.updatedAt = cachedUsage.updatedAt
            recovered.status = .available
            recovered.freshness = .stale(lastSuccessAt: cached.succeededAt)
        } else {
            if recovered.sessionTokens == nil { recovered.sessionTokens = cachedUsage.sessionTokens }
            if recovered.last30DaysTokens == nil { recovered.last30DaysTokens = cachedUsage.last30DaysTokens }
            if recovered.sessionCostUSD == nil { recovered.sessionCostUSD = cachedUsage.sessionCostUSD }
            if recovered.last30DaysCostUSD == nil { recovered.last30DaysCostUSD = cachedUsage.last30DaysCostUSD }
            if recovered.currencyCode.isEmpty { recovered.currencyCode = cachedUsage.currencyCode }
            if recovered.detailText?.isEmpty != false { recovered.detailText = cachedUsage.detailText }
            if recovered.usageWindows.isEmpty { recovered.usageWindows = cachedUsage.usageWindows }
            if recovered.sourceLabel?.isEmpty != false { recovered.sourceLabel = cachedUsage.sourceLabel }
            if recovered.strategyID?.isEmpty != false { recovered.strategyID = cachedUsage.strategyID }
            if recovered.accountEmail?.isEmpty != false { recovered.accountEmail = cachedUsage.accountEmail }
            if recovered.accountPlan?.isEmpty != false { recovered.accountPlan = cachedUsage.accountPlan }
            if recovered.cliVersion?.isEmpty != false { recovered.cliVersion = cachedUsage.cliVersion }
            if recovered.updatedAt == nil { recovered.updatedAt = cachedUsage.updatedAt }
            recovered.status = .available
            recovered.freshness = .degraded(lastSuccessAt: cached.succeededAt)
        }

        recovered.diagnosis = diagnosis
        _ = now
        return recovered
    }

    public func persist() throws {
        let data = try JSONEncoder().encode(Archive(entries: entries))
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).tmp")
        try data.write(to: temporaryURL)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }
}
