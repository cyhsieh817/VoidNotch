import Foundation

public protocol TokenUsageProviding: Sendable {
    func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsageFetchResult]
}

public struct UnavailableTokenUsageProvider: TokenUsageProviding {
    public init() {}

    public func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsageFetchResult] {
        let observedAt = Date()
        return providers.map {
            ProviderUsageFetchResult(
                usage: ProviderUsage(
                    provider: $0,
                    status: .unavailable,
                    errorMessage: "Token usage provider unavailable"),
                diagnosis: UsageFetchDiagnosis(
                    kind: .unsupported,
                    rawMessage: "Token usage provider unavailable",
                    observedAt: observedAt))
        }
    }
}

public struct StaticTokenUsageProvider: TokenUsageProviding {
    private let snapshots: [ProviderUsage]

    public init(_ snapshots: [ProviderUsage]) {
        self.snapshots = snapshots
    }

    public func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsageFetchResult] {
        let byProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        return providers.map {
            ProviderUsageFetchResult(usage: byProvider[$0] ?? ProviderUsage.placeholder(for: $0))
        }
    }
}
