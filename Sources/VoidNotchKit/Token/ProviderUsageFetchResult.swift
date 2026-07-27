import Foundation

public struct ProviderUsageFetchResult: Sendable, Equatable {
    public var usage: ProviderUsage
    public var dailyHistory: [TokenDailyRecord]
    public var diagnosis: UsageFetchDiagnosis?

    public init(
        usage: ProviderUsage,
        dailyHistory: [TokenDailyRecord] = [],
        diagnosis: UsageFetchDiagnosis? = nil)
    {
        self.usage = usage
        self.dailyHistory = dailyHistory
        self.diagnosis = diagnosis
    }
}
