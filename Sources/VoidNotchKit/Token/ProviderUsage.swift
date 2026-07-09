import Foundation

public struct ProviderUsageWindow: Identifiable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var kind: ProviderUsageWindowKind
    public var usedPercent: Int
    public var remainingPercent: Int
    public var windowMinutes: Int?
    public var resetsAt: Date?
    public var resetDescription: String?
    public var usageKnown: Bool

    public init(
        id: String,
        title: String,
        kind: ProviderUsageWindowKind,
        usedPercent: Int,
        remainingPercent: Int,
        windowMinutes: Int? = nil,
        resetsAt: Date? = nil,
        resetDescription: String? = nil,
        usageKnown: Bool = true)
    {
        self.id = id
        self.title = title
        self.kind = kind
        self.usedPercent = min(100, max(0, usedPercent))
        self.remainingPercent = min(100, max(0, remainingPercent))
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription.map(Self.normalizedResetDescription)
        self.usageKnown = usageKnown
    }

    public func percent(for mode: TokenUsageDisplayMode) -> Int {
        switch mode {
        case .remaining: return remainingPercent
        case .used: return usedPercent
        }
    }

    public func metricText(for mode: TokenUsageDisplayMode) -> String {
        "\(mode.label) \(percent(for: mode))%"
    }

    public var resetText: String? {
        if let resetDescription, !resetDescription.isEmpty {
            return resetDescription
        }
        guard let resetsAt else { return nil }

        let seconds = Int(resetsAt.timeIntervalSinceNow.rounded())
        guard seconds > 0 else { return "Reset pending" }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return remainingHours > 0 ? "Reset in \(days)d \(remainingHours)h" : "Reset in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "Reset in \(hours)h \(minutes)m" : "Reset in \(hours)h"
        }
        return "Reset in \(max(1, minutes))m"
    }

    private static func normalizedResetDescription(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(
            of: #"(?i)\b(Resets?)(?=[A-Z0-9])"#,
            with: "$1 ",
            options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"(?i)\b(Resets?)\b\s*"#,
            with: "$1 ",
            options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"(?i)(?<=[A-Za-z0-9])at(?=[0-9])"#,
            with: " at ",
            options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"(?<=[A-Za-z])(?=[0-9])"#,
            with: " ",
            options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression)
        return text
    }
}

public struct ProviderUsage: Identifiable, Sendable, Equatable {
    public let provider: TokenProviderKind
    public var status: ProviderUsageStatus
    public var usedPercent: Int
    public var sessionTokens: Int?
    public var last30DaysTokens: Int?
    public var sessionCostUSD: Double?
    public var last30DaysCostUSD: Double?
    public var currencyCode: String
    public var updatedAt: Date?
    public var errorMessage: String?
    public var detailText: String?
    public var usageWindows: [ProviderUsageWindow]
    public var sourceLabel: String?
    public var strategyID: String?
    public var accountEmail: String?
    public var accountPlan: String?
    public var cliVersion: String?

    public var id: String { provider.id }
    public var name: String { provider.displayName }

    public init(
        provider: TokenProviderKind,
        status: ProviderUsageStatus = .idle,
        usedPercent: Int = 0,
        sessionTokens: Int? = nil,
        last30DaysTokens: Int? = nil,
        sessionCostUSD: Double? = nil,
        last30DaysCostUSD: Double? = nil,
        currencyCode: String = "USD",
        updatedAt: Date? = nil,
        errorMessage: String? = nil,
        detailText: String? = nil,
        usageWindows: [ProviderUsageWindow] = [],
        sourceLabel: String? = nil,
        strategyID: String? = nil,
        accountEmail: String? = nil,
        accountPlan: String? = nil,
        cliVersion: String? = nil)
    {
        self.provider = provider
        self.status = status
        self.usedPercent = usedPercent
        self.sessionTokens = sessionTokens
        self.last30DaysTokens = last30DaysTokens
        self.sessionCostUSD = sessionCostUSD
        self.last30DaysCostUSD = last30DaysCostUSD
        self.currencyCode = currencyCode
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
        self.detailText = detailText
        self.usageWindows = usageWindows
        self.sourceLabel = sourceLabel
        self.strategyID = strategyID
        self.accountEmail = accountEmail
        self.accountPlan = accountPlan
        self.cliVersion = cliVersion
    }

    public static func placeholder(for provider: TokenProviderKind) -> ProviderUsage {
        ProviderUsage(provider: provider)
    }

    public static func percentage(sessionTokens: Int?, totalTokens: Int?) -> Int {
        guard let sessionTokens, let totalTokens, totalTokens > 0 else { return 0 }
        let value = (Double(sessionTokens) / Double(totalTokens) * 100).rounded()
        return min(100, max(0, Int(value)))
    }

    public var compactText: String {
        compactText(for: .used)
    }

    public func compactText(for mode: TokenUsageDisplayMode) -> String {
        if status == .refreshing {
            return "..."
        }
        if let primaryWindow {
            return "\(primaryWindow.percent(for: mode))%"
        }
        if let sessionTokens {
            return Self.abbreviatedTokens(sessionTokens)
        }
        if status == .unsupported {
            return "n/a"
        }
        return "\(usedPercent)%"
    }

    public var primaryMetricText: String {
        primaryMetricText(for: .used)
    }

    public func primaryMetricText(for mode: TokenUsageDisplayMode) -> String {
        if let sessionTokens {
            return Self.abbreviatedTokens(sessionTokens)
        }
        if let primaryWindow {
            return "\(primaryWindow.percent(for: mode))%"
        }
        if status == .available {
            return "\(usedPercent)%"
        }
        return status.label
    }

    public var secondaryMetricText: String {
        if let detailText {
            return detailText
        }
        let month = last30DaysTokensText
        let cost = Self.costText(last30DaysCostUSD, currencyCode: currencyCode)
        return "30d \(month) / \(cost)"
    }

    public var sessionTokensText: String {
        Self.tokenText(sessionTokens)
    }

    public var last30DaysTokensText: String {
        Self.tokenText(last30DaysTokens)
    }

    public var sessionCostText: String {
        Self.costText(sessionCostUSD, currencyCode: currencyCode)
    }

    public var last30DaysCostText: String {
        Self.costText(last30DaysCostUSD, currencyCode: currencyCode)
    }

    public var hasTokenOrCostData: Bool {
        sessionTokens != nil || last30DaysTokens != nil || sessionCostUSD != nil || last30DaysCostUSD != nil
    }

    public var hasAnyUsageData: Bool {
        hasTokenOrCostData || !usageWindows.isEmpty || status == .available
    }

    public var statusDetailText: String {
        switch status {
        case .idle:
            return "Waiting for first refresh"
        case .refreshing:
            return "Refreshing local provider data"
        case .available:
            return dataCoverageText
        case .unsupported:
            return "Adapter not implemented for this provider yet"
        case .unavailable:
            return errorMessage ?? "No local records or provider session found"
        }
    }

    public var dataCoverageText: String {
        var parts: [String] = []
        if !usageWindows.isEmpty {
            parts.append("\(usageWindows.count) quota window\(usageWindows.count == 1 ? "" : "s")")
        }
        if sessionTokens != nil {
            parts.append("session tokens")
        }
        if last30DaysTokens != nil {
            parts.append("30d tokens")
        }
        if sessionCostUSD != nil || last30DaysCostUSD != nil {
            parts.append("cost")
        }
        if parts.isEmpty {
            return provider.expectedDataText
        }
        return parts.joined(separator: " / ")
    }

    public var sourceSummaryText: String {
        let source = sourceLabel?.isEmpty == false ? sourceLabel! : provider.settingsDetail
        if let strategyID, !strategyID.isEmpty {
            return "\(source) · \(strategyID)"
        }
        return source
    }

    public var identitySummaryText: String {
        var parts: [String] = []
        if accountEmail?.isEmpty == false { parts.append(accountEmail!) }
        if accountPlan?.isEmpty == false { parts.append(accountPlan!) }
        return parts.isEmpty ? "No account metadata" : parts.joined(separator: " · ")
    }

    public var providerActionHint: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }

        switch status {
        case .idle, .refreshing, .available:
            return provider.expectedDataText
        case .unsupported:
            return "Shown intentionally so unsupported providers are not mistaken for zero usage."
        case .unavailable:
            return "Open the provider app or CLI once, then refresh VoidNotch."
        }
    }

    public var primaryWindow: ProviderUsageWindow? {
        usageWindows.first(where: \.usageKnown) ?? usageWindows.first
    }

    public var sortedUsageWindows: [ProviderUsageWindow] {
        usageWindows.sorted { lhs, rhs in
            let lhsRank = Self.windowSortRank(lhs)
            let rhsRank = Self.windowSortRank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    public var updatedText: String? {
        updatedAt?.formatted(date: .omitted, time: .shortened)
    }

    public var sourceText: String {
        sourceLabel?.isEmpty == false ? sourceLabel! : "-"
    }

    public var versionText: String {
        cliVersion?.isEmpty == false ? cliVersion! : "-"
    }

    public var accountText: String {
        accountEmail?.isEmpty == false ? accountEmail! : "-"
    }

    public var planText: String {
        accountPlan?.isEmpty == false ? accountPlan! : "-"
    }

    private static func tokenText(_ value: Int?) -> String {
        value.map(abbreviatedTokens) ?? "-"
    }

    private static func abbreviatedTokens(_ value: Int) -> String {
        let number = Double(value)
        if abs(value) >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        }
        if abs(value) >= 1_000 {
            return String(format: "%.1fK", number / 1_000)
        }
        return "\(value)"
    }

    private static func costText(_ value: Double?, currencyCode: String) -> String {
        guard let value else { return "-" }
        let symbol = currencyCode.uppercased() == "USD" ? "$" : "\(currencyCode.uppercased()) "
        return "\(symbol)\(String(format: "%.2f", value))"
    }

    private static func windowSortRank(_ window: ProviderUsageWindow) -> Int {
        switch window.kind {
        case .fiveHour: return 0
        case .weekly: return 1
        case .monthly: return 2
        case .model: return 3
        case .other: return 4
        }
    }
}
