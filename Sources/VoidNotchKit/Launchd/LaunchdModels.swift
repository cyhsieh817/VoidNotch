import Foundation

/// launchd agent harness、排程與執行狀態的純資料模型。
public enum AgentHarnessKind: String, CaseIterable, Sendable, Codable, Equatable {
    case claude
    case codex
    case gemini
    case grok
    case hermes
    case voidweaver
    case omlx
    case other

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .hermes: "Hermes"
        case .voidweaver: "VoidWeaver"
        case .omlx: "oMLX"
        case .other: "Other"
        }
    }
}

/// StartCalendarInterval 的單一欄位集合。
public struct LaunchdCalendarSpec: Sendable, Equatable {
    public var minute: Int?
    public var hour: Int?
    public var day: Int?
    public var weekday: Int?
    public var month: Int?

    public init(
        minute: Int? = nil,
        hour: Int? = nil,
        day: Int? = nil,
        weekday: Int? = nil,
        month: Int? = nil
    ) {
        self.minute = minute
        self.hour = hour
        self.day = day
        self.weekday = weekday
        self.month = month
    }
}

/// launchd 可觀測到的排程型態。
public enum LaunchdScheduleKind: Sendable, Equatable {
    case interval(seconds: Int)
    case calendar([LaunchdCalendarSpec])
    case watchPaths([String])
    case keepAlive
    case runAtLoadOnly
    case onDemand
}

/// launchctl list 對單一 job 回報的執行狀態。
public struct LaunchdRuntimeState: Sendable, Equatable {
    public var pid: Int?
    public var lastExitStatus: Int?

    public init(pid: Int? = nil, lastExitStatus: Int? = nil) {
        self.pid = pid
        self.lastExitStatus = lastExitStatus
    }
}

/// job 在掃描結果中的生命週期階段。
public enum LaunchdJobPhase: String, CaseIterable, Sendable, Equatable {
    case run
    case paused
    case archived
}

/// 一份 launchd plist 與其 runtime 狀態合併後的統一模型。
public struct LaunchdJob: Identifiable, Sendable, Equatable {
    public var id: String { plistPath }
    public var label: String
    public var plistPath: String
    public var harness: AgentHarnessKind
    public var programSummary: String
    public var schedule: LaunchdScheduleKind
    public var isDisabled: Bool
    public var isLoaded: Bool
    public var pid: Int?
    public var lastExitStatus: Int?
    public var phase: LaunchdJobPhase
    /// 已封存、但檔名仍會被 launchd 載入 → 下次登入會復活的殭屍。
    public var isZombie: Bool

    public init(
        label: String,
        plistPath: String,
        harness: AgentHarnessKind,
        programSummary: String,
        schedule: LaunchdScheduleKind,
        isDisabled: Bool,
        isLoaded: Bool = false,
        pid: Int? = nil,
        lastExitStatus: Int? = nil,
        phase: LaunchdJobPhase = .paused,
        isZombie: Bool = false
    ) {
        self.label = label
        self.plistPath = plistPath
        self.harness = harness
        self.programSummary = programSummary
        self.schedule = schedule
        self.isDisabled = isDisabled
        self.isLoaded = isLoaded
        self.pid = pid
        self.lastExitStatus = lastExitStatus
        self.phase = phase
        self.isZombie = isZombie
    }
}

/// 依 launchd label 將 job 歸入已知 agent harness。
///
/// 以非英數字元（`.` `-` `_` 空白等）切成 token 後做完整比對，
/// 避免 `htmlxform`、`pilgdrive` 這類子字串誤判為 harness。
public enum LaunchdHarnessClassifier: Sendable {
    public static func classify(label: String) -> AgentHarnessKind {
        let tokens = tokens(from: label)

        if tokens.contains("claude") || tokens.contains("anthropic") {
            return .claude
        }
        if tokens.contains("codex") || tokens.contains("openai") {
            return .codex
        }
        if tokens.contains("gemini") || tokens.contains("agy") || tokens.contains("antigravity") {
            return .gemini
        }
        if tokens.contains("grok") || tokens.contains("xai") {
            return .grok
        }
        if tokens.contains("hermes") {
            return .hermes
        }
        if tokens.contains("voidweaver") || tokens.contains("voidnotch") ||
            tokens.contains("lgd") || tokens.contains("labgrimoire") {
            return .voidweaver
        }
        if tokens.contains("omlx") || tokens.contains("osaurus") || tokens.contains("mlx") {
            return .omlx
        }
        return .other
    }

    /// 將 label 以非英數字元切成 lowercased token。
    private static func tokens(from label: String) -> Set<String> {
        let lowered = label.lowercased()
        let parts = lowered.split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init).filter { !$0.isEmpty })
    }
}

/// 將排程轉成給人閱讀的中英文摘要。
public enum LaunchdScheduleFormatter: Sendable {
    public static func text(for schedule: LaunchdScheduleKind, zhHant: Bool) -> String {
        switch schedule {
        case .interval(let seconds):
            return zhHant ? "每 \(seconds) 秒" : "Every \(seconds)s"
        case .calendar(let specs):
            let separator = zhHant ? "、" : ", "
            return specs.map { calendarText($0, zhHant: zhHant) }.joined(separator: separator)
        case .watchPaths:
            return zhHant ? "監看路徑" : "Watch paths"
        case .keepAlive:
            return zhHant ? "常駐 (KeepAlive)" : "Always on (KeepAlive)"
        case .runAtLoadOnly:
            return zhHant ? "登入時執行" : "At login"
        case .onDemand:
            return zhHant ? "按需啟動" : "On demand"
        }
    }

    private static func calendarText(_ spec: LaunchdCalendarSpec, zhHant: Bool) -> String {
        let dateParts = [
            spec.weekday.map { weekdayText($0, zhHant: zhHant) },
            spec.month.map { zhHant ? "\($0)月" : "Month \($0)" },
            spec.day.map { zhHant ? "\($0)日" : "Day \($0)" }
        ].compactMap { $0 }

        let time: String?
        if spec.hour == nil, let minute = spec.minute {
            time = ":\(twoDigits(minute))"
        } else if spec.hour != nil || spec.minute != nil {
            time = "\(twoDigits(spec.hour ?? 0)):\(twoDigits(spec.minute ?? 0))"
        } else {
            time = nil
        }

        if dateParts.isEmpty, spec.hour == nil, spec.minute != nil {
            return zhHant ? "每小時 \(time ?? "")" : "Hourly \(time ?? "")"
        }
        if dateParts.isEmpty {
            if let time {
                return zhHant ? "每日 \(time)" : "Daily \(time)"
            }
            return zhHant ? "每日" : "Daily"
        }
        if let time {
            return dateParts.joined(separator: " ") + " " + time
        }
        return dateParts.joined(separator: " ")
    }

    private static func weekdayText(_ weekday: Int, zhHant: Bool) -> String {
        let names = zhHant
            ? ["週日", "週一", "週二", "週三", "週四", "週五", "週六"]
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let normalized = weekday == 7 ? 0 : weekday
        guard names.indices.contains(normalized) else {
            return zhHant ? "週\(weekday)" : "Weekday \(weekday)"
        }
        return names[normalized]
    }

    private static func twoDigits(_ value: Int) -> String {
        value >= 0 && value < 10 ? "0\(value)" : String(value)
    }
}
