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

        let maxBytes = max(1, maxReadBytes)
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return [] }
        defer { try? handle.close() }

        let truncated = fileSize > UInt64(maxBytes)
        let startOffset = truncated ? fileSize - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: startOffset)) != nil,
              let data = try? handle.read(upToCount: maxBytes)
        else { return [] }

        // 位元組切割可能落在多位元組 UTF-8 字元中間；向前推進切點直到可解碼。
        guard var text = Self.decodeTailUTF8(from: data, truncated: truncated) else { return [] }

        if truncated {
            guard let firstNewline = text.firstIndex(where: \.isNewline) else {
                return []
            }
            text = String(text[text.index(after: firstNewline)...])
        }

        let cutoff = Date().addingTimeInterval(-retentionSeconds)
        return AgentEventLogParser.parse(text: text, retentionCutoff: cutoff)
    }

    /// 若尾端切在 UTF-8 序列中間，向前跳過最多 3 個位元組再解碼。
    private static func decodeTailUTF8(from data: Data, truncated: Bool) -> String? {
        guard !data.isEmpty else { return "" }
        if !truncated {
            return String(data: data, encoding: .utf8)
        }

        // 不完整前導最多 3 bytes（UTF-8 最長 4，開頭已佔 1）
        for skip in 0...3 {
            guard skip < data.count else { break }
            let slice = data.subdata(in: skip..<data.count)
            if let text = String(data: slice, encoding: .utf8) {
                return text
            }
        }
        return nil
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
