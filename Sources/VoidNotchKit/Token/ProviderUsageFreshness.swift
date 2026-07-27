import Foundation

public enum ProviderUsageFreshness: Sendable, Equatable, Codable {
    case fresh
    case degraded(lastSuccessAt: Date)
    case stale(lastSuccessAt: Date)

    public var lastSuccessAt: Date? {
        switch self {
        case .fresh:
            return nil
        case let .degraded(lastSuccessAt), let .stale(lastSuccessAt):
            return lastSuccessAt
        }
    }

    public var isFresh: Bool {
        if case .fresh = self {
            return true
        }
        return false
    }

    public func age(now: Date) -> TimeInterval? {
        guard let lastSuccessAt else { return nil }
        return max(0, now.timeIntervalSince(lastSuccessAt))
    }

    public func ageText(now: Date) -> String? {
        guard let age = age(now: now) else { return nil }

        if age < 60 {
            return "just now"
        }
        if age < 3600 {
            return "\(Int(age / 60))m ago"
        }
        if age < 86400 {
            return "\(Int(age / 3600))h ago"
        }
        return "\(Int(age / 86400))d ago"
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case lastSuccessAt
    }

    private enum Kind: String, Codable {
        case fresh
        case degraded
        case stale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .fresh:
            self = .fresh
        case .degraded:
            self = .degraded(lastSuccessAt: try container.decode(Date.self, forKey: .lastSuccessAt))
        case .stale:
            self = .stale(lastSuccessAt: try container.decode(Date.self, forKey: .lastSuccessAt))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .fresh:
            try container.encode(Kind.fresh, forKey: .kind)
        case let .degraded(lastSuccessAt):
            try container.encode(Kind.degraded, forKey: .kind)
            try container.encode(lastSuccessAt, forKey: .lastSuccessAt)
        case let .stale(lastSuccessAt):
            try container.encode(Kind.stale, forKey: .kind)
            try container.encode(lastSuccessAt, forKey: .lastSuccessAt)
        }
    }
}
