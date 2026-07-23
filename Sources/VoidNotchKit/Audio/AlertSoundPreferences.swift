import Foundation

public enum AlertSoundCategory: String, CaseIterable, Hashable, Sendable {
    case sessionStart
    case taskComplete
    case inputRequired
    case taskError
    case resourceLimit

    public init?(status: AgentActivityStatus?) {
        switch status {
        case .started: self = .sessionStart
        case .completed: self = .taskComplete
        case .needsInput: self = .inputRequired
        case .failed: self = .taskError
        case .resourceLimit: self = .resourceLimit
        case .running, .stopped, nil: return nil
        }
    }

    public var packCategoryName: String {
        switch self {
        case .sessionStart: return "session.start"
        case .taskComplete: return "task.complete"
        case .inputRequired: return "input.required"
        case .taskError: return "task.error"
        case .resourceLimit: return "resource.limit"
        }
    }
}

public enum AlertSoundSourceKind: String, CaseIterable, Sendable {
    case soundPack
    case system
    case localFile
}

public struct AlertSoundSelection: Equatable, Sendable {
    public let kind: AlertSoundSourceKind
    public let value: String?

    public init(kind: AlertSoundSourceKind, value: String? = nil) {
        self.kind = kind
        self.value = value
    }

    public static let soundPack = AlertSoundSelection(kind: .soundPack)
}

public final class AlertSoundPreferences {
    public static let systemSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    private static let keyPrefix = "VoidNotch.notifications.sound."

    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    public init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    public func selection(for category: AlertSoundCategory) -> AlertSoundSelection {
        guard let rawKind = userDefaults.string(forKey: key(for: category, component: "kind")),
              let kind = AlertSoundSourceKind(rawValue: rawKind)
        else { return .soundPack }

        return AlertSoundSelection(
            kind: kind,
            value: userDefaults.string(forKey: key(for: category, component: "value")))
    }

    public func setSelection(_ selection: AlertSoundSelection, for category: AlertSoundCategory) {
        userDefaults.set(selection.kind.rawValue, forKey: key(for: category, component: "kind"))
        let valueKey = key(for: category, component: "value")
        if let value = selection.value {
            userDefaults.set(value, forKey: valueKey)
        } else {
            userDefaults.removeObject(forKey: valueKey)
        }
    }

    public func resolvedLocalFileURL(for category: AlertSoundCategory) -> URL? {
        let selection = selection(for: category)
        guard selection.kind == .localFile else { return nil }
        return resolvedLocalFileURL(from: selection.value)
    }

    public func resolvedLocalFileURL(from path: String?) -> URL? {
        guard let path,
              !path.isEmpty,
              NSString(string: path).isAbsolutePath
        else { return nil }

        let url = URL(fileURLWithPath: path, isDirectory: false)
        guard url.isFileURL,
              fileManager.isReadableFile(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular
        else { return nil }

        return url
    }

    private func key(for category: AlertSoundCategory, component: String) -> String {
        Self.keyPrefix + category.rawValue + "." + component
    }
}
