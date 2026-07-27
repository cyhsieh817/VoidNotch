import Foundation

public struct TokenDailyRecord: Sendable, Equatable, Codable {
    public let date: String
    public let provider: String
    public var costUsd: Double?
    public var tokens: Int?

    public init(date: String, provider: String, costUsd: Double?, tokens: Int?) {
        self.date = date
        self.provider = provider
        self.costUsd = costUsd
        self.tokens = tokens
    }
}

public struct TokenDailyArchive: Sendable, Equatable, Codable {
    public var version: Int
    public var days: [TokenDailyRecord]

    public init(version: Int = 1, days: [TokenDailyRecord]) {
        self.version = version
        self.days = days
    }
}

public enum TokenDailyMerge {
    public static func normalizedDateString(_ date: Date, calendar: Calendar) -> String {
        var localCalendar = calendar
        localCalendar.locale = Locale(identifier: "en_US_POSIX")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = localCalendar
        formatter.timeZone = localCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func merge(
        archive: [TokenDailyRecord],
        incoming: [TokenDailyRecord],
        retentionDays: Int,
        today: String) -> [TokenDailyRecord]
    {
        let effectiveRetentionDays = max(1, retentionDays)
        let cutoff = retentionCutoff(today: today, retentionDays: effectiveRetentionDays)
        var records: [RecordKey: TokenDailyRecord] = [:]

        for record in archive where shouldKeep(record, cutoff: cutoff, today: today) {
            records[RecordKey(record)] = mergedRecord(records[RecordKey(record)], with: record)
        }

        let validIncoming = incoming.filter {
            shouldKeep($0, cutoff: cutoff, today: today)
                && ($0.costUsd != nil || $0.tokens != nil)
        }
        var oldestIncomingDateByProvider: [String: String] = [:]
        for record in validIncoming {
            if let oldestDate = oldestIncomingDateByProvider[record.provider] {
                if record.date < oldestDate {
                    oldestIncomingDateByProvider[record.provider] = record.date
                }
            } else {
                oldestIncomingDateByProvider[record.provider] = record.date
            }
        }

        for record in validIncoming {
            let isOldestDate = oldestIncomingDateByProvider[record.provider] == record.date
            records[RecordKey(record)] = mergedIncomingRecord(
                records[RecordKey(record)],
                with: record,
                isOldestDate: isOldestDate)
        }

        return records.values.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.provider < $1.provider
        }
    }

    private struct RecordKey: Hashable {
        let date: String
        let provider: String

        init(_ record: TokenDailyRecord) {
            self.date = record.date
            self.provider = record.provider
        }
    }

    private static func shouldKeep(
        _ record: TokenDailyRecord,
        cutoff: String,
        today: String) -> Bool
    {
        isDateString(record.date) && record.date >= cutoff && record.date <= today
    }

    private static func isDateString(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else { return false }

        for index in 0..<bytes.count where index != 4 && index != 7 {
            guard bytes[index] >= 48 && bytes[index] <= 57 else { return false }
        }
        return true
    }

    private static func mergedRecord(
        _ existing: TokenDailyRecord?,
        with incoming: TokenDailyRecord) -> TokenDailyRecord
    {
        guard let existing else { return incoming }
        return TokenDailyRecord(
            date: existing.date,
            provider: existing.provider,
            costUsd: maximum(existing.costUsd, incoming.costUsd),
            tokens: maximum(existing.tokens, incoming.tokens))
    }

    private static func mergedIncomingRecord(
        _ existing: TokenDailyRecord?,
        with incoming: TokenDailyRecord,
        isOldestDate: Bool) -> TokenDailyRecord
    {
        guard let existing else { return incoming }

        return TokenDailyRecord(
            date: existing.date,
            provider: existing.provider,
            costUsd: isOldestDate
                ? maximum(existing.costUsd, incoming.costUsd)
                : incoming.costUsd ?? existing.costUsd,
            tokens: isOldestDate
                ? maximum(existing.tokens, incoming.tokens)
                : incoming.tokens ?? existing.tokens)
    }

    private static func maximum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): return max(lhs, rhs)
        case let (value?, nil), let (nil, value?): return value
        case (nil, nil): return nil
        }
    }

    private static func maximum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): return max(lhs, rhs)
        case let (value?, nil), let (nil, value?): return value
        case (nil, nil): return nil
        }
    }

    private static func retentionCutoff(today: String, retentionDays: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        guard let todayDate = formatter.date(from: today),
              let cutoffDate = calendar.date(
                  byAdding: .day,
                  value: -(retentionDays - 1),
                  to: todayDate)
        else {
            return today
        }
        return formatter.string(from: cutoffDate)
    }
}

public final class TokenDailyStore: @unchecked Sendable {
    public static let currentVersion: Int = 1

    private struct FileFingerprint: Equatable {
        let modificationDate: Date
        let size: UInt64
        let systemFileNumber: UInt64
    }

    public static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoidNotch/token-daily.json")
    }

    private let fileURL: URL
    private let retentionDays: Int
    private let calendar: Calendar
    private let fileManager = FileManager.default
    private let cacheLock = NSLock()
    private var cachedFingerprint: FileFingerprint?
    private var cachedRecords: [TokenDailyRecord] = []

    public init(
        fileURL: URL = TokenDailyStore.defaultFileURL(),
        retentionDays: Int = 400,
        calendar: Calendar = .current)
    {
        self.fileURL = fileURL
        self.retentionDays = retentionDays
        self.calendar = calendar
    }

    /// Same directory as `fileURL`, filename `"<originalName>.unreadable.bak"`.
    public func preservedBackupURL() -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).unreadable.bak")
    }

    public func load() -> [TokenDailyRecord] {
        let fingerprint = fileFingerprint()

        cacheLock.lock()
        if let fingerprint, cachedFingerprint == fingerprint {
            let records = cachedRecords
            cacheLock.unlock()
            return records
        }
        cacheLock.unlock()

        guard let archive = decodeArchive() else { return [] }
        guard let fingerprint else { return archive.days }

        cacheLock.lock()
        cachedFingerprint = fingerprint
        cachedRecords = archive.days
        let records = cachedRecords
        cacheLock.unlock()
        return records
    }

    @discardableResult
    public func ingest(_ incoming: [TokenDailyRecord], now: Date) throws -> [TokenDailyRecord] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let today = TokenDailyMerge.normalizedDateString(now, calendar: calendar)
        let merged = TokenDailyMerge.merge(
            archive: loadLocked(),
            incoming: incoming,
            retentionDays: retentionDays,
            today: today)

        preserveUnreadableArchiveIfNeeded()

        let archive = TokenDailyArchive(version: Self.currentVersion, days: merged)
        let data = try JSONEncoder().encode(archive)
        try writeAtomically(data)

        guard let fingerprint = fileFingerprint() else {
            cachedFingerprint = nil
            cachedRecords = []
            return merged
        }
        cachedFingerprint = fingerprint
        cachedRecords = merged
        return merged
    }

    public func series(provider: String?, days: Int, endingAt: Date) -> [TokenDailyRecord] {
        guard days > 0 else { return [] }

        let endingDate = TokenDailyMerge.normalizedDateString(endingAt, calendar: calendar)
        let startDate = calendar.date(
            byAdding: .day,
            value: -(days - 1),
            to: endingAt)
        let startDateString = startDate.map {
            TokenDailyMerge.normalizedDateString($0, calendar: calendar)
        } ?? endingDate

        return load()
            .filter {
                $0.date >= startDateString
                    && $0.date <= endingDate
                    && (provider == nil || $0.provider == provider)
            }
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.provider < $1.provider
            }
    }

    private func loadLocked() -> [TokenDailyRecord] {
        let fingerprint = fileFingerprint()
        if let fingerprint, cachedFingerprint == fingerprint {
            return cachedRecords
        }

        guard let archive = decodeArchive() else { return [] }
        guard let fingerprint else { return archive.days }

        cachedFingerprint = fingerprint
        cachedRecords = archive.days
        return archive.days
    }

    private func decodeArchive() -> TokenDailyArchive? {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(TokenDailyArchive.self, from: data),
              archive.version == Self.currentVersion
        else {
            return nil
        }
        return archive
    }

    private func fileFingerprint() -> FileFingerprint? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let systemFileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else {
            return nil
        }

        return FileFingerprint(
            modificationDate: modificationDate,
            size: size,
            systemFileNumber: systemFileNumber)
    }

    /// Before overwrite: if the existing archive file is present but unreadable
    /// (invalid JSON or version ≠ currentVersion), copy it once to
    /// `preservedBackupURL()`. Failures are swallowed so ingest can proceed.
    private func preserveUnreadableArchiveIfNeeded() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let isReadable: Bool = {
            guard let data = try? Data(contentsOf: fileURL),
                  let archive = try? JSONDecoder().decode(TokenDailyArchive.self, from: data),
                  archive.version == Self.currentVersion
            else {
                return false
            }
            return true
        }()
        guard !isReadable else { return }

        let backupURL = preservedBackupURL()
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }

        try? fileManager.copyItem(at: fileURL, to: backupURL)
    }

    private func writeAtomically(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try data.write(to: temporaryURL)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }
}
