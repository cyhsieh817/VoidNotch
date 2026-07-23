import Foundation

public struct CodexHookAdapter: AgentHookAdapter {
    public let kind: AgentActivityProviderKind = .codex
    private let fs: FileSystemReading

    static let events = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop"]
    static let relayMarker = "--voidnotch-relay"

    public init(fs: FileSystemReading) { self.fs = fs }

    public func detect(fs: FileSystemReading, paths: HookPaths) -> HookStatus {
        let url = paths.codexHooks
        guard fs.fileExists(url) || fs.fileExists(paths.home.appendingPathComponent(".codex")) else {
            return .agentAbsent
        }
        guard let data = fs.readData(url) else { return .notInstalled }
        guard let text = String(data: data, encoding: .utf8) else { return .conflict("hooks.json 非 UTF-8") }
        if (try? JSONSerialization.jsonObject(with: data)) == nil {
            return .conflict("hooks.json 解析失敗")
        }
        return text.contains(Self.relayMarker) ? .installed : .notInstalled
    }

    public func plan(paths: HookPaths) throws -> [HookMutation] {
        let url = paths.codexHooks
        var root: [String: Any] = [:]
        if let data = fs.readData(url) {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookPlanError.malformed("~/.codex/hooks.json 解析失敗")
            }
            root = obj
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // 路徑含空格（~/Library/Application Support/…），必須加引號否則 shell 拆字
        let command = "bash \"\(paths.installedRelay.path)\" --provider codex \(Self.relayMarker)"

        for event in Self.events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            let hasRelay = entries.contains { entry in
                let inner = entry["hooks"] as? [[String: Any]] ?? []
                return inner.contains { ($0["command"] as? String)?.contains(Self.relayMarker) == true }
            }
            if !hasRelay {
                entries.append(["hooks": [["type": "command", "command": command]]])
            }
            hooks[event] = entries
        }
        root["hooks"] = hooks

        let newData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        var muts: [HookMutation] = []
        if fs.fileExists(url) { muts.append(.backup(url)) }
        muts.append(.writeJSON(url, newData))
        return muts
    }
}
