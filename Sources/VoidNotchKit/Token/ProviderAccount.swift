import Foundation

public struct ProviderAccount: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var provider: TokenProviderKind
    public var label: String
    public var externalIdentifier: String?
    public var addedAt: Date?
    public var lastUsedAt: Date?
    public var isActive: Bool
    public var isDisabled: Bool
    public var disabledReason: String?

    public init(
        id: UUID,
        provider: TokenProviderKind,
        label: String,
        externalIdentifier: String? = nil,
        addedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        isActive: Bool = false,
        isDisabled: Bool = false,
        disabledReason: String? = nil)
    {
        self.id = id
        self.provider = provider
        self.label = label
        self.externalIdentifier = externalIdentifier
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.disabledReason = disabledReason
    }

    public var displaySubtitle: String {
        if isDisabled {
            let normalizedReason = disabledReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedReason?.isEmpty == false {
                return normalizedReason!
            }
            return "Skipped account"
        }
        let normalizedIdentifier = externalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedIdentifier?.isEmpty == false {
            return normalizedIdentifier!
        }
        return isActive ? "Active account" : "Saved account"
    }
}

public struct ProviderAccountUsage: Identifiable, Sendable, Equatable {
    public var account: ProviderAccount
    public var usage: ProviderUsage
    public var isRecommended: Bool

    public init(
        account: ProviderAccount,
        usage: ProviderUsage,
        isRecommended: Bool = false)
    {
        self.account = account
        self.usage = usage
        self.isRecommended = isRecommended
    }

    public var id: UUID { account.id }

    public var recommendationScore: Int? {
        guard !account.isDisabled else { return nil }
        guard usage.status == .available else { return nil }
        if let primaryWindow = usage.primaryWindow, primaryWindow.usageKnown {
            return primaryWindow.remainingPercent
        }
        guard usage.hasTokenOrCostData || usage.usedPercent > 0 else { return nil }
        return min(100, max(0, 100 - usage.usedPercent))
    }

    public var quotaSummaryText: String {
        if let primaryWindow = usage.primaryWindow {
            return "\(primaryWindow.title) \(primaryWindow.remainingPercent)% left"
        }
        if usage.status == .available {
            return usage.primaryMetricText(for: .remaining)
        }
        if let errorMessage = usage.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        return usage.status.label
    }

    public var detailSummaryText: String {
        if let detailText = usage.detailText, !detailText.isEmpty {
            return detailText
        }
        if usage.identitySummaryText != "No account metadata" {
            return usage.identitySummaryText
        }
        return account.displaySubtitle
    }
}

public struct ProviderAccountExport: Sendable, Equatable {
    public var provider: TokenProviderKind
    public var fileName: String
    public var payload: String
    public var accountCount: Int

    public init(
        provider: TokenProviderKind,
        fileName: String,
        payload: String,
        accountCount: Int)
    {
        self.provider = provider
        self.fileName = fileName
        self.payload = payload
        self.accountCount = accountCount
    }
}

public struct ProviderAccountImport: Sendable, Equatable {
    public var label: String?
    public var rawValue: String

    public init(label: String? = nil, rawValue: String) {
        self.label = label
        self.rawValue = rawValue
    }

    public var normalizedLabel: String? {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    public var normalizedRawValue: String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol TokenAccountManaging: Sendable {
    func loadAccounts(for provider: TokenProviderKind) async throws -> [ProviderAccount]
    func loadAccountUsages(for provider: TokenProviderKind) async throws -> [ProviderAccountUsage]
    func setActiveAccount(_ accountID: UUID, for provider: TokenProviderKind) async throws
    func setAccountDisabled(_ accountID: UUID, disabled: Bool, reason: String?, for provider: TokenProviderKind) async throws
    func deleteAccount(_ accountID: UUID, for provider: TokenProviderKind) async throws
    func importAccount(for provider: TokenProviderKind) async throws -> ProviderAccount?
    func importAccounts(_ accountImport: ProviderAccountImport, for provider: TokenProviderKind) async throws -> [ProviderAccount]
    func exportAccounts(_ accountIDs: [UUID], for provider: TokenProviderKind) async throws -> ProviderAccountExport
}

public extension TokenAccountManaging {
    func loadAccountUsages(for provider: TokenProviderKind) async throws -> [ProviderAccountUsage] {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }

    func importAccount(for provider: TokenProviderKind) async throws -> ProviderAccount? {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }

    func importAccounts(_ accountImport: ProviderAccountImport, for provider: TokenProviderKind) async throws -> [ProviderAccount] {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }

    func setAccountDisabled(_ accountID: UUID, disabled: Bool, reason: String?, for provider: TokenProviderKind) async throws {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }

    func exportAccounts(_ accountIDs: [UUID], for provider: TokenProviderKind) async throws -> ProviderAccountExport {
        throw TokenAccountManagementError.unsupportedProvider(provider)
    }
}

public enum TokenAccountManagementError: LocalizedError, Sendable, Equatable {
    case unsupportedProvider(TokenProviderKind)
    case accountNotFound
    case accountDisabled
    case noImportableAccount(TokenProviderKind)
    case invalidImportData(TokenProviderKind)
    case noExportableAccount(TokenProviderKind)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProvider(provider):
            return "\(provider.displayName) does not support account switching."
        case .accountNotFound:
            return "The selected account no longer exists."
        case .accountDisabled:
            return "The selected account is skipped."
        case let .noImportableAccount(provider):
            return "No importable \(provider.displayName) account was found."
        case let .invalidImportData(provider):
            return "The pasted \(provider.displayName) account data could not be imported."
        case let .noExportableAccount(provider):
            return "No exportable \(provider.displayName) account was found."
        }
    }
}
