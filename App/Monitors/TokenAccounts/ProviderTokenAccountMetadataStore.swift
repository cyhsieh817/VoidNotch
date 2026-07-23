//
//  ProviderTokenAccountMetadataStore.swift
//

#if canImport(CodexBarCore)
import Foundation
import CodexBarCore

struct ProviderTokenAccountMetadata: Codable, Sendable, Equatable {
    var isDisabled: Bool
    var disabledReason: String?
}

struct ProviderTokenAccountMetadataStore: @unchecked Sendable {
    private static let fileLock = NSLock()

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadMetadata(for provider: UsageProvider) throws -> [String: ProviderTokenAccountMetadata] {
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }
        return try loadFileUnlocked().providers[provider.rawValue] ?? [:]
    }

    func setMetadata(
        _ metadata: ProviderTokenAccountMetadata?,
        for accountID: UUID,
        provider: UsageProvider) throws
    {
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }

        var file = try loadFileUnlocked()
        var providerMetadata = file.providers[provider.rawValue] ?? [:]
        providerMetadata[accountID.uuidString] = metadata
        if providerMetadata.isEmpty {
            file.providers.removeValue(forKey: provider.rawValue)
        } else {
            file.providers[provider.rawValue] = providerMetadata
        }
        try storeFileUnlocked(file)
    }

    func removeMetadata(for accountID: UUID, provider: UsageProvider) throws {
        try setMetadata(nil, for: accountID, provider: provider)
    }

    private func loadFileUnlocked() throws -> ProviderTokenAccountMetadataFile {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ProviderTokenAccountMetadataFile(version: 1, providers: [:])
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ProviderTokenAccountMetadataFile.self, from: data)
    }

    private func storeFileUnlocked(_ file: ProviderTokenAccountMetadataFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: fileURL, options: [.atomic])
        #if os(macOS) || os(Linux)
        try fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: fileURL.path)
        #endif
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("VoidNotch", isDirectory: true)
            .appendingPathComponent("provider-account-metadata.json")
    }
}

private struct ProviderTokenAccountMetadataFile: Codable {
    var version: Int
    var providers: [String: [String: ProviderTokenAccountMetadata]]
}
#endif

