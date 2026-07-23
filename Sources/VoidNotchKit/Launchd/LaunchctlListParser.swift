import Foundation

/// 解析 launchctl list 的純文字輸出，不執行任何 Process 或檔案 I/O。
public enum LaunchctlListParser: Sendable {
    public static func parse(_ output: String) -> [String: LaunchdRuntimeState] {
        var states: [String: LaunchdRuntimeState] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 3 else {
                continue
            }
            if fields[0] == "PID", fields[1] == "Status", fields[2] == "Label" {
                continue
            }

            let pid: Int?
            if fields[0] == "-" {
                pid = nil
            } else if let parsedPID = Int(fields[0]) {
                pid = parsedPID
            } else {
                continue
            }
            guard let status = Int(fields[1]) else {
                continue
            }

            let label = fields.dropFirst(2).map(String.init).joined(separator: " ")
            guard !label.isEmpty else {
                continue
            }
            states[label] = LaunchdRuntimeState(pid: pid, lastExitStatus: status)
        }

        return states
    }
}
