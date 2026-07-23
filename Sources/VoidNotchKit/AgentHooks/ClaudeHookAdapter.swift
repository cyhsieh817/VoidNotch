import Foundation

public struct ClaudeHookAdapter: AgentHookAdapter {
    public let kind: AgentActivityProviderKind = .claude
    private let fs: FileSystemReading

    static let events = ["SessionStart", "UserPromptSubmit", "Notification", "PermissionRequest", "Stop"]
    static let relayMarker = "--voidnotch-relay"
    static let inputBrokerMarker = "--voidnotch-input-broker"

    public init(fs: FileSystemReading) { self.fs = fs }

    public func detect(fs: FileSystemReading, paths: HookPaths) -> HookStatus {
        // Claude 家目錄以 settings.json 或 ~/.claude 目錄存在判定
        let settings = paths.claudeSettings
        guard fs.fileExists(settings) || fs.fileExists(paths.home.appendingPathComponent(".claude")) else {
            return .agentAbsent
        }
        guard let data = fs.readData(settings) else { return .notInstalled }
        guard let text = String(data: data, encoding: .utf8) else { return .conflict("settings.json 非 UTF-8") }
        if (try? JSONSerialization.jsonObject(with: data)) == nil {
            return .conflict("settings.json 解析失敗")
        }
        return text.contains(Self.relayMarker) && text.contains(Self.inputBrokerMarker) ? .installed : .notInstalled
    }

    public func plan(paths: HookPaths) throws -> [HookMutation] {
        let url = paths.claudeSettings
        var root: [String: Any] = [:]
        if let data = fs.readData(url) {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookPlanError.malformed("~/.claude/settings.json 解析失敗")
            }
            root = obj
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let command = "bash \"\(paths.installedRelay.path)\" --provider claude \(Self.relayMarker)"

        for event in Self.events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            // 移除 peon.sh；並檢查是否已含 relay
            var hasRelay = false
            entries = entries.compactMap { entry -> [String: Any]? in
                var e = entry
                var inner = e["hooks"] as? [[String: Any]] ?? []
                inner.removeAll { ($0["command"] as? String)?.contains("peon-ping/peon.sh") == true }
                if inner.contains(where: { ($0["command"] as? String)?.contains(Self.relayMarker) == true }) {
                    hasRelay = true
                }
                if inner.isEmpty && (e["hooks"] != nil) { return nil }
                e["hooks"] = inner
                return e
            }
            if !hasRelay {
                entries.append(["matcher": "", "hooks": [["type": "command", "command": command, "timeout": 10]]])
            }
            hooks[event] = entries
        }
        var preTool = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preTool.removeAll { entry in
            (entry["hooks"] as? [[String: Any]])?.contains(where: {
                ($0["command"] as? String)?.contains(Self.inputBrokerMarker) == true
            }) == true
        }
        preTool.append([
            "matcher": "AskUserQuestion",
            "hooks": [["type": "command", "command": command + " \(Self.inputBrokerMarker)", "timeout": 600]],
        ])
        hooks["PreToolUse"] = preTool
        root["hooks"] = hooks

        let newData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        var muts: [HookMutation] = []
        if fs.fileExists(url) { muts.append(.backup(url)) }
        muts.append(.writeJSON(url, newData))
        return muts
    }
}
