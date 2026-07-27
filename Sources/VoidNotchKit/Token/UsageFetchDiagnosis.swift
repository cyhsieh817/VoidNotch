import Foundation

public enum UsageFetchFailureKind: String, Sendable, Codable, CaseIterable {
    case network
    case authentication
    case rateLimited
    case schemaDrift
    case noUsableData
    case unsupported
    case unknown

    public var isAutoRetryable: Bool {
        switch self {
        case .network, .rateLimited:
            return true
        case .authentication, .schemaDrift, .noUsableData, .unsupported, .unknown:
            return false
        }
    }

    public var requiresUserAction: Bool {
        self == .authentication
    }
}

public struct UsageFetchDiagnosis: Sendable, Equatable, Codable {
    public let kind: UsageFetchFailureKind
    public let rawMessage: String?
    public let retryAfter: TimeInterval?
    public let observedAt: Date

    public init(
        kind: UsageFetchFailureKind,
        rawMessage: String? = nil,
        retryAfter: TimeInterval? = nil,
        observedAt: Date)
    {
        self.kind = kind
        self.rawMessage = rawMessage
        self.retryAfter = retryAfter
        self.observedAt = observedAt
    }
}

public enum UsageFailureTextClassifier {
    public static func classify(_ description: String) -> UsageFetchFailureKind {
        let text = description.lowercased()

        if text.contains("429") || text.contains("rate limit") || text.contains("too many request") {
            return .rateLimited
        }
        if text.contains("401") || text.contains("403") || text.contains("unauthor") ||
            text.contains("unauthenticated") || text.contains("credential") ||
            text.contains("log in") || text.contains("login") || text.contains("token expired") {
            return .authentication
        }
        if text.contains("timed out") || text.contains("timeout") || text.contains("offline") ||
            text.contains("network") || text.contains("connection") ||
            text.contains("could not connect") || text.contains("host") {
            return .network
        }
        if text.contains("unsupported") {
            return .unsupported
        }
        if text.contains("no usable data") {
            return .noUsableData
        }
        if text.contains("decod") || text.contains("parse") || text.contains("missing field") ||
            text.contains("unexpected") || text.contains("keynotfound") {
            return .schemaDrift
        }
        return .unknown
    }
}
