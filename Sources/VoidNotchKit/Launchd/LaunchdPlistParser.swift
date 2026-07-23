import Foundation

/// 解析 launchd plist，將原始 Property List 轉為 VoidNotchKit 模型。
public enum LaunchdPlistParser: Sendable {
    public static func job(fromPlistData data: Data, plistPath: String) -> LaunchdJob? {
        guard let propertyList = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ),
        let dictionary = propertyList as? [String: Any],
        let label = dictionary["Label"] as? String else {
            return nil
        }

        let programSummary: String
        if let arguments = dictionary["ProgramArguments"] as? [String] {
            programSummary = arguments.joined(separator: " ")
        } else {
            programSummary = dictionary["Program"] as? String ?? ""
        }

        let isDisabled = boolValue(dictionary["Disabled"])
        let job = LaunchdJob(
            label: label,
            plistPath: plistPath,
            harness: LaunchdHarnessClassifier.classify(label: label),
            programSummary: programSummary,
            schedule: schedule(from: dictionary),
            isDisabled: isDisabled,
            // phase 三態唯一權威在 LaunchdScheduleScanner（合併 runtime 後判定），parser 不預判。
            phase: .paused
        )
        return job
    }

    private static func schedule(from dictionary: [String: Any]) -> LaunchdScheduleKind {
        if let seconds = integerValue(dictionary["StartInterval"]) {
            return .interval(seconds: seconds)
        }
        if let calendar = calendarSpecs(from: dictionary["StartCalendarInterval"]) {
            return .calendar(calendar)
        }
        if let paths = stringArray(dictionary["WatchPaths"]) {
            return .watchPaths(paths)
        }
        if let paths = stringArray(dictionary["QueueDirectories"]) {
            return .watchPaths(paths)
        }
        if isKeepAlive(dictionary["KeepAlive"]) {
            return .keepAlive
        }
        if boolValue(dictionary["RunAtLoad"]) {
            return .runAtLoadOnly
        }
        return .onDemand
    }

    private static func calendarSpecs(from value: Any?) -> [LaunchdCalendarSpec]? {
        if let dictionary = value as? [String: Any] {
            return [calendarSpec(from: dictionary)]
        }
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries.map { calendarSpec(from: $0) }
        }
        return nil
    }

    private static func calendarSpec(from dictionary: [String: Any]) -> LaunchdCalendarSpec {
        LaunchdCalendarSpec(
            minute: integerValue(dictionary["Minute"]),
            hour: integerValue(dictionary["Hour"]),
            day: integerValue(dictionary["Day"]),
            weekday: integerValue(dictionary["Weekday"]),
            month: integerValue(dictionary["Month"])
        )
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        value as? [String]
    }

    private static func isKeepAlive(_ value: Any?) -> Bool {
        if boolValue(value) {
            return true
        }
        if let dictionary = value as? [String: Any] {
            return !dictionary.isEmpty
        }
        return false
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return Int(exactly: value.int64Value)
        }
        return nil
    }
}
