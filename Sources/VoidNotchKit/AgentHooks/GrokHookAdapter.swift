import Foundation

/// Grok 透過 [compat.claude] hooks 直接掃 ~/.claude/settings.json，
/// 故不需獨立寫入；relay 靠 GROK_WORKSPACE_ROOT env 分辨 provider。
public struct GrokHookAdapter: AgentHookAdapter {
    public let kind: AgentActivityProviderKind = .grok
    private let fs: FileSystemReading

    public init(fs: FileSystemReading) { self.fs = fs }

    private func compatHooksDisabled(_ text: String) -> Bool {
        // 逐行解析：真 TOML 表頭界定段、去行內註解、key 錨定精確比對
        var inCompatClaude = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }  // 去行內註解
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inCompatClaude = (trimmed == "[compat.claude]")
                continue
            }
            guard inCompatClaude else { continue }
            if trimmed.replacingOccurrences(of: " ", with: "") == "hooks=false" { return true }
        }
        return false
    }

    public func detect(fs: FileSystemReading, paths: HookPaths) -> HookStatus {
        let config = paths.grokConfig
        guard fs.fileExists(config) || fs.fileExists(paths.home.appendingPathComponent(".grok")) else {
            return .agentAbsent
        }
        if let data = fs.readData(config), let text = String(data: data, encoding: .utf8),
           compatHooksDisabled(text) {
            return .conflict("~/.grok/config.toml 的 [compat.claude] hooks 已關閉，Grok 無法搭 Claude 便車")
        }
        // Grok 狀態鏡射 Claude：Claude settings 已含 relay marker 才算 installed
        if let data = fs.readData(paths.claudeSettings), let text = String(data: data, encoding: .utf8),
           text.contains("--voidnotch-relay") {
            return .installed
        }
        return .notInstalled
    }

    public func plan(paths: HookPaths) throws -> [HookMutation] { [] }  // 唯讀
}
