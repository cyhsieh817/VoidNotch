import Foundation

/// Pure-logic peon sound pack: path resolution, manifest decode, path-traversal guards.
public final class PeonSoundPack {
    public struct Manifest: Decodable {
        public let categories: [String: Category]
    }

    public struct Category: Decodable {
        public let sounds: [Sound]
    }

    public struct Sound: Decodable {
        public let file: String
    }

    public let packURL: URL
    public let manifest: Manifest?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default)
    {
        if let override = environment["VOIDNOTCH_PEON_PACK"], !override.isEmpty {
            if override == "~" {
                packURL = fileManager.homeDirectoryForCurrentUser
            } else if override.hasPrefix("~/") {
                packURL = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(String(override.dropFirst(2)), isDirectory: true)
            } else if override.hasPrefix("/") {
                packURL = URL(fileURLWithPath: override, isDirectory: true)
            } else {
                packURL = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(override, isDirectory: true)
            }
        } else {
            packURL = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/hooks/peon-ping/packs/peon", isDirectory: true)
        }

        let manifestURL = packURL.appendingPathComponent("openpeon.json", isDirectory: false)
        if let data = try? Data(contentsOf: manifestURL) {
            manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        } else {
            manifest = nil
        }
    }

    public func categoryName(for status: AgentActivityStatus) -> String? {
        switch status {
        case .started: return "session.start"
        case .completed: return "task.complete"
        case .needsInput: return "input.required"
        case .failed: return "task.error"
        case .resourceLimit: return "resource.limit"
        case .running, .stopped: return nil
        }
    }

    public func validatedSoundURL(for file: String) -> URL? {
        let root = packURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = packURL.appendingPathComponent(file).resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath),
              FileManager.default.isReadableFile(atPath: candidate.path)
        else { return nil }
        return candidate
    }
}
