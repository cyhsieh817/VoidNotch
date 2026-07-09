//
//  AgentEventLogReader.swift — JSONL event-log file reader
//
//  Keeps file IO and tail-window handling testable from the Swift package.
//

import Foundation

public enum AgentEventLogReader {
    public static let defaultMaxReadBytes = 256 * 1024

    public static func loadEvents(
        from url: URL,
        maxReadBytes: Int = defaultMaxReadBytes,
        retentionSeconds: TimeInterval,
        createDirectoryIfMissing: Bool = false,
        fileManager: FileManager = .default
    ) -> [AgentActivityEvent] {
        if createDirectoryIfMissing {
            ensureParentDirectory(for: url, fileManager: fileManager)
        }

        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return [] }

        let maxBytes = max(1, maxReadBytes)
        let tailData = data.count > maxBytes ? Data(data.suffix(maxBytes)) : data
        guard var text = String(data: tailData, encoding: .utf8) else { return [] }

        if data.count > maxBytes {
            guard let firstNewline = text.firstIndex(where: \.isNewline) else {
                return []
            }
            text = String(text[text.index(after: firstNewline)...])
        }

        let cutoff = Date().addingTimeInterval(-retentionSeconds)
        return AgentEventLogParser.parse(text: text, retentionCutoff: cutoff)
    }

    @discardableResult
    public static func ensureParentDirectory(
        for url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let directory = url.deletingLastPathComponent()
        guard !directory.path.isEmpty else { return true }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}
