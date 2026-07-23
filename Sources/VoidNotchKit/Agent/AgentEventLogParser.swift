//
//  AgentEventLogParser.swift — PeonPing event-log (JSONL) 解析器
//
//  Extracted from PeonPingAgentActivityProvider in App/Monitors/AgentActivityStore.swift.
//  retentionCutoff 可注入以利測試。
//

import Foundation
import VoidNotchSpeechKit

/// PeonPing event-log(JSONL)解析。從檔案 IO 抽離,retentionCutoff 可注入以利測試。
public enum AgentEventLogParser {
    /// 解析整段文字(每行一筆),保留 occurredAt >= cutoff 者。
    public static func parse(text: String, retentionCutoff: Date) -> [AgentActivityEvent] {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap(parseEventLine)
            .filter { $0.occurredAt >= retentionCutoff }
    }

    /// 解析單行;格式不符或 provider/status 無法判定時回 nil。
    public static func parseEventLine(_ line: String) -> AgentActivityEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any]
        else { return nil }

        guard let provider = provider(from: payload),
              let status = status(from: payload)
        else { return nil }

        let occurredAt = dateValue(from: payload) ?? Date()
        return AgentActivityEvent(
            id: uuidValue(from: payload) ?? UUID(),
            provider: provider,
            status: status,
            title: title(from: payload, provider: provider, status: status),
            detail: detail(from: payload),
            workspace: workspace(from: payload),
            occurredAt: occurredAt,
            durationSeconds: doubleValue(for: "duration_seconds", in: payload)
                ?? doubleValue(for: "durationSeconds", in: payload),
            inputRequest: inputRequest(from: payload),
            navigation: navigation(from: payload))
    }

    private static func navigation(from payload: [String: Any]) -> AgentNavigationTarget? {
        guard let object = payload["navigation"] as? [String: Any] else { return nil }

        let rawSurface = navigationStringValue(for: "source_surface", in: object)
            ?? navigationStringValue(for: "sourceSurface", in: object)
        let sourceSurface = rawSurface.flatMap {
            AgentNavigationSourceSurface(rawValue: $0)
        } ?? .unknown

        return AgentNavigationTarget(
            sourceSurface: sourceSurface,
            sessionID: nonEmptyNavigationString(for: "session_id", in: object),
            tmuxSocket: absolutePathNavigationString(for: "tmux_socket", in: object),
            tmuxPane: matchingNavigationString(for: "tmux_pane", pattern: #"^%[0-9]+$"#, in: object),
            tmuxWindow: matchingNavigationString(for: "tmux_window", pattern: #"^@[0-9]+$"#, in: object),
            tmuxSession: nonEmptyNavigationString(for: "tmux_session", in: object),
            tmuxClientTTY: matchingNavigationString(
                for: "tmux_client_tty",
                pattern: #"^/dev/tty[A-Za-z0-9._-]+$"#,
                in: object))
    }

    private static func navigationStringValue(for key: String, in payload: [String: Any]) -> String? {
        guard let value = payload[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return nil
        }
        return trimmed
    }

    private static func nonEmptyNavigationString(for key: String, in payload: [String: Any]) -> String? {
        navigationStringValue(for: key, in: payload)
    }

    private static func absolutePathNavigationString(for key: String, in payload: [String: Any]) -> String? {
        guard let value = navigationStringValue(for: key, in: payload), value.hasPrefix("/") else {
            return nil
        }
        return value
    }

    private static func matchingNavigationString(
        for key: String,
        pattern: String,
        in payload: [String: Any]) -> String?
    {
        guard let value = navigationStringValue(for: key, in: payload),
              value.range(of: pattern, options: .regularExpression) != nil
        else { return nil }
        return value
    }

    private static func inputRequest(from payload: [String: Any]) -> AgentInputRequest? {
        guard let object = payload["input_request"] as? [String: Any],
              let rawID = object["request_id"] as? String,
              let requestID = UUID(uuidString: rawID),
              let rawQuestions = object["questions"] as? [[String: Any]], !rawQuestions.isEmpty
        else { return nil }
        let questions = rawQuestions.compactMap { item -> AgentInputQuestion? in
            guard let question = item["question"] as? String, !question.isEmpty,
                  let header = item["header"] as? String,
                  let rawOptions = item["options"] as? [[String: Any]], !rawOptions.isEmpty
            else { return nil }
            let options = rawOptions.compactMap { option -> AgentInputOption? in
                guard let label = option["label"] as? String, !label.isEmpty,
                      let description = option["description"] as? String
                else { return nil }
                return AgentInputOption(label: label, description: description)
            }
            guard options.count == rawOptions.count else { return nil }
            guard AgentSpeechOptionMatcher.isValid(labels: options.map(\.label)) else { return nil }
            return AgentInputQuestion(question: question, header: header, options: options,
                                      multiSelect: item["multiSelect"] as? Bool ?? false)
        }
        guard questions.count == rawQuestions.count else { return nil }
        return AgentInputRequest(requestID: requestID, questions: questions)
    }

    // MARK: - Private helpers (moved verbatim from PeonPingAgentActivityProvider)

    private static func provider(from payload: [String: Any]) -> AgentActivityProviderKind? {
        let candidates = [
            "provider",
            "agent",
            "client",
            "runtime",
            "tool",
            "source",
        ]
        for key in candidates {
            if let provider = provider(from: stringValue(for: key, in: payload)) {
                return provider
            }
        }
        return nil
    }

    private static func provider(from rawValue: String?) -> AgentActivityProviderKind? {
        guard let rawValue else { return nil }
        let value = rawValue.lowercased()
        if value.contains("codex") { return .codex }
        if value.contains("claude") { return .claude }
        if value.contains("gemini") || value.contains("agy") || value.contains("antigravity") {
            return .antigravity
        }
        if value.contains("grok") { return .grok }
        if value == "pi" { return .pi }   // 精確比對：避免 copilot / api 等含 "pi" 子字串誤判
        return nil
    }

    private static func status(from payload: [String: Any]) -> AgentActivityStatus? {
        let candidates = [
            "status",
            "category",
            "cesp",
            "hook_event_name",
            "hookEventName",
            "event",
            "event_name",
            "eventName",
        ]
        for key in candidates {
            if let status = status(from: stringValue(for: key, in: payload)) {
                return status
            }
        }
        return nil
    }

    private static func status(from rawValue: String?) -> AgentActivityStatus? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "sessionstart", "sessionstarted", "sessionstartcategory":
            return .started
        case "started", "start":
            return .started
        case "userpromptsubmit", "turnstart", "subagentstart", "running", "taskrunning":
            return .running
        case "stop", "taskcomplete", "turnend", "completed", "complete":
            return .completed
        case "notification", "permissionrequest", "inputrequired", "needsinput":
            return .needsInput
        case "posttoolusefailure", "taskerror", "failed", "failure", "error":
            return .failed
        case "precompact", "resourcelimit", "contextlimit", "tokenlimit":
            return .resourceLimit
        case "sessionend", "stopped", "stoprequested", "shutdown":
            return .stopped
        default:
            return nil
        }
    }

    private static func title(
        from payload: [String: Any],
        provider: AgentActivityProviderKind,
        status: AgentActivityStatus) -> String
    {
        if let title = stringValue(for: "title", in: payload), !title.isEmpty {
            return title
        }

        switch status {
        case .started:
            return "\(provider.displayName) started"
        case .running:
            return "\(provider.displayName) working"
        case .needsInput:
            return "\(provider.displayName) needs input"
        case .completed:
            return "\(provider.displayName) completed"
        case .failed:
            return "\(provider.displayName) error"
        case .resourceLimit:
            return "\(provider.displayName) resource limit"
        case .stopped:
            return "\(provider.displayName) stopped"
        }
    }

    private static func detail(from payload: [String: Any]) -> String? {
        for key in ["detail", "message", "body", "summary", "error", "tool_name"] {
            if let value = stringValue(for: key, in: payload), !value.isEmpty {
                return value
            }
        }

        let hook = stringValue(for: "hook_event_name", in: payload) ?? stringValue(for: "event", in: payload)
        let category = stringValue(for: "category", in: payload) ?? stringValue(for: "cesp", in: payload)
        return [hook, category]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private static func workspace(from payload: [String: Any]) -> String? {
        for key in ["workspace", "workspace_name", "project", "repo"] {
            if let value = stringValue(for: key, in: payload), !value.isEmpty {
                return value
            }
        }

        guard let cwd = stringValue(for: "cwd", in: payload), !cwd.isEmpty else { return nil }
        let workspace = URL(fileURLWithPath: NSString(string: cwd).expandingTildeInPath).lastPathComponent
        return workspace.isEmpty ? nil : workspace
    }

    private static func uuidValue(from payload: [String: Any]) -> UUID? {
        for key in ["id", "event_id", "eventId"] {
            if let value = stringValue(for: key, in: payload),
               let uuid = UUID(uuidString: value)
            {
                return uuid
            }
        }
        return nil
    }

    private static func dateValue(from payload: [String: Any]) -> Date? {
        for key in ["timestamp", "ts", "time", "occurred_at", "occurredAt"] {
            if let timestamp = doubleValue(for: key, in: payload) {
                return Date(timeIntervalSince1970: timestamp)
            }
            if let value = stringValue(for: key, in: payload),
               let date = parseDate(value)
            {
                return date
            }
        }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }

    private static func stringValue(for key: String, in payload: [String: Any]) -> String? {
        switch payload[key] {
        case let value as String:
            return value
        case let value as CustomStringConvertible:
            return value.description
        default:
            return nil
        }
    }

    private static func doubleValue(for key: String, in payload: [String: Any]) -> Double? {
        switch payload[key] {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
