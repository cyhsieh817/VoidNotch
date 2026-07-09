import Foundation

public protocol TokenUsageProviding: Sendable {
    func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsage]
}

public struct UnavailableTokenUsageProvider: TokenUsageProviding {
    public init() {}

    public func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsage] {
        providers.map {
            ProviderUsage(
                provider: $0,
                status: .unavailable,
                errorMessage: "Token usage provider unavailable")
        }
    }
}

public struct StaticTokenUsageProvider: TokenUsageProviding {
    private let snapshots: [ProviderUsage]

    public init(_ snapshots: [ProviderUsage]) {
        self.snapshots = snapshots
    }

    public func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsage] {
        let byProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        return providers.map { byProvider[$0] ?? ProviderUsage.placeholder(for: $0) }
    }
}
