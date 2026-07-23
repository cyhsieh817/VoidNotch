import Foundation

public struct PiHookAdapter: AgentHookAdapter {
    public let kind: AgentActivityProviderKind = .pi
    private let fs: FileSystemReading

    /// 擴充內含這個字串才算「夠新」。舊版只發通知、沒有 question 工具，
    /// 若只看檔案在不在就判 installed，既有使用者會永遠停在舊版拿不到瀏海問答。
    /// 改動 broker 協議時，這裡與 voidnotch.ts 的 QUESTION_TOOL_MARKER 要一起升號。
    static let questionToolMarker = "voidnotch-question-tool-v1"

    public init(fs: FileSystemReading) { self.fs = fs }

    public func detect(fs: FileSystemReading, paths: HookPaths) -> HookStatus {
        guard fs.fileExists(paths.home.appendingPathComponent(".pi/agent")) else { return .agentAbsent }
        guard let data = fs.readData(paths.installedPiExtension),
              let text = String(data: data, encoding: .utf8)
        else { return .notInstalled }
        return text.contains(Self.questionToolMarker) ? .installed : .notInstalled
    }

    public func plan(paths: HookPaths) throws -> [HookMutation] {
        [.copyFile(from: paths.bundledPiExtension, to: paths.installedPiExtension)]
    }
}
