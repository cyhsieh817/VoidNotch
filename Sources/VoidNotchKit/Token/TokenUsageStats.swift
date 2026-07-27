import Foundation

/// Pure aggregation helpers over `[TokenDailyRecord]` for Settings detail views.
/// All inputs are in-memory; no file I/O or calendar side effects.
public enum TokenUsageStats {
    public struct Summary: Sendable, Equatable {
        public let totalCost: Double
        public let totalTokens: Int
        public let activeDays: Int
        public let dailyAverageCost: Double
        public let peakDay: PeakDay?
        public let earliestDate: String?
        public let latestDate: String?

        public init(
            totalCost: Double,
            totalTokens: Int,
            activeDays: Int,
            dailyAverageCost: Double,
            peakDay: PeakDay?,
            earliestDate: String?,
            latestDate: String?)
        {
            self.totalCost = totalCost
            self.totalTokens = totalTokens
            self.activeDays = activeDays
            self.dailyAverageCost = dailyAverageCost
            self.peakDay = peakDay
            self.earliestDate = earliestDate
            self.latestDate = latestDate
        }
    }

    public struct PeakDay: Sendable, Equatable {
        public let date: String
        public let cost: Double

        public init(date: String, cost: Double) {
            self.date = date
            self.cost = cost
        }
    }

    public struct ProviderSummary: Sendable, Equatable {
        public let provider: String
        public let totalCost: Double
        public let totalTokens: Int
        public let activeDays: Int
        /// Fraction of grand total cost in `0...1`. Zero when grand total is zero.
        public let costShare: Double

        public init(
            provider: String,
            totalCost: Double,
            totalTokens: Int,
            activeDays: Int,
            costShare: Double)
        {
            self.provider = provider
            self.totalCost = totalCost
            self.totalTokens = totalTokens
            self.activeDays = activeDays
            self.costShare = costShare
        }
    }

    public struct DailyRow: Sendable, Equatable {
        public let date: String
        public let provider: String
        public let costUsd: Double
        public let tokens: Int

        public init(date: String, provider: String, costUsd: Double, tokens: Int) {
            self.date = date
            self.provider = provider
            self.costUsd = costUsd
            self.tokens = tokens
        }
    }

    /// Overall totals, active-day average, and peak day across all providers.
    public static func summary(records: [TokenDailyRecord]) -> Summary {
        guard !records.isEmpty else {
            return Summary(
                totalCost: 0,
                totalTokens: 0,
                activeDays: 0,
                dailyAverageCost: 0,
                peakDay: nil,
                earliestDate: nil,
                latestDate: nil)
        }

        var totalCost = 0.0
        var totalTokens = 0
        var costByDate: [String: Double] = [:]
        var earliestDate: String?
        var latestDate: String?

        for record in records {
            let cost = costValue(record.costUsd)
            let tokens = tokensValue(record.tokens)
            totalCost += cost
            totalTokens += tokens
            costByDate[record.date, default: 0] += cost

            if let earliest = earliestDate {
                if record.date < earliest { earliestDate = record.date }
            } else {
                earliestDate = record.date
            }
            if let latest = latestDate {
                if record.date > latest { latestDate = record.date }
            } else {
                latestDate = record.date
            }
        }

        let activeDays = costByDate.values.filter { $0 > 0 }.count
        let dailyAverageCost = activeDays > 0 ? totalCost / Double(activeDays) : 0

        let peakDay: PeakDay? = costByDate.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            // Tie-break: prefer the later calendar day for stable peak selection.
            return lhs.key < rhs.key
        }.map { PeakDay(date: $0.key, cost: $0.value) }

        return Summary(
            totalCost: totalCost,
            totalTokens: totalTokens,
            activeDays: activeDays,
            dailyAverageCost: dailyAverageCost,
            peakDay: peakDay,
            earliestDate: earliestDate,
            latestDate: latestDate)
    }

    /// Per-provider rollups, sorted by `totalCost` descending then provider name ascending.
    public static func byProvider(records: [TokenDailyRecord]) -> [ProviderSummary] {
        guard !records.isEmpty else { return [] }

        var totals: [String: (cost: Double, tokens: Int)] = [:]
        var activeDatesByProvider: [String: Set<String>] = [:]

        for record in records {
            let cost = costValue(record.costUsd)
            let tokens = tokensValue(record.tokens)
            let existing = totals[record.provider] ?? (0, 0)
            totals[record.provider] = (existing.cost + cost, existing.tokens + tokens)
            if cost > 0 {
                activeDatesByProvider[record.provider, default: []].insert(record.date)
            }
        }

        let grandTotalCost = totals.values.reduce(0.0) { $0 + $1.cost }

        return totals
            .map { provider, totals in
                let costShare = grandTotalCost > 0 ? totals.cost / grandTotalCost : 0
                return ProviderSummary(
                    provider: provider,
                    totalCost: totals.cost,
                    totalTokens: totals.tokens,
                    activeDays: activeDatesByProvider[provider]?.count ?? 0,
                    costShare: costShare)
            }
            .sorted {
                if $0.totalCost != $1.totalCost { return $0.totalCost > $1.totalCost }
                return $0.provider < $1.provider
            }
    }

    /// One row per record (nil metrics as 0), newest date first; same day by cost descending.
    public static func dailyRows(records: [TokenDailyRecord]) -> [DailyRow] {
        records
            .map {
                DailyRow(
                    date: $0.date,
                    provider: $0.provider,
                    costUsd: costValue($0.costUsd),
                    tokens: tokensValue($0.tokens))
            }
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                if $0.costUsd != $1.costUsd { return $0.costUsd > $1.costUsd }
                return $0.provider < $1.provider
            }
    }

    // MARK: - Private

    private static func costValue(_ value: Double?) -> Double {
        value ?? 0
    }

    private static func tokensValue(_ value: Int?) -> Int {
        value ?? 0
    }
}
