import Foundation

public enum AgentInputResponseWriter {
    public static func write(request: AgentInputRequest, selections: [Int: Set<String>]) throws {
        var answers: [String: String] = [:]
        for (index, question) in request.questions.enumerated() {
            let selected = selections[index] ?? []
            let allowed = Set(question.options.map(\.label))
            guard !selected.isEmpty, selected.isSubset(of: allowed), question.multiSelect || selected.count == 1 else {
                // 1570 = NSValidationMissingMandatoryPropertyError (NSCocoaErrorDomain)
                throw CocoaError(CocoaError.Code(rawValue: 1570))
            }
            answers[question.question] = question.options.map(\.label).filter(selected.contains).joined(separator: ", ")
        }
        try writeResponse(requestID: request.requestID, body: ["answers": answers])
    }

    /// 使用者關掉卡片／卡片逾時而未作答：通知 relay 放棄接管，好讓 agent 立刻在原本的終端機提問。
    /// 少了這一步，relay 會一路空等到 broker timeout（預設 590 秒），使用者反而比沒裝 VoidNotch 還慢。
    public static func dismiss(request: AgentInputRequest) throws {
        try writeResponse(requestID: request.requestID, body: ["dismissed": true])
    }

    private static func writeResponse(requestID: UUID, body: [String: Any]) throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = support.appendingPathComponent("VoidNotch/responses", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // relay 的 request_id 由 python uuid4() 產生（小寫），而 Swift 的 UUID.uuidString 一律大寫。
        // 檔名與欄位都轉小寫，兩端才對得上。
        let id = requestID.uuidString.lowercased()
        let destination = directory.appendingPathComponent(id + ".json")
        var payload = body
        payload["request_id"] = id
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: destination, options: .atomic)
    }
}
