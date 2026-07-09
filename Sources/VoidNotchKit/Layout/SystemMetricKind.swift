import Foundation

/// Selectable system metrics for compact strip and expanded System panel.
public enum SystemMetricKind: String, CaseIterable, Sendable, Identifiable {
    case cpu
    case memory
    case disk
    case network
    case battery
    case temperature
    case health
    case host
    case processes
    case gpu

    public var id: String { rawValue }

    /// Short label (EN source of truth).
    public var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .battery: return "Battery"
        case .temperature: return "Temp"
        case .health: return "Health"
        case .host: return "Host"
        case .processes: return "Processes"
        case .gpu: return "GPU"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .battery: return "battery.100"
        case .temperature: return "thermometer.medium"
        case .health: return "heart.text.square"
        case .host: return "desktopcomputer"
        case .processes: return "list.bullet"
        case .gpu: return "display"
        }
    }

    /// Metrics that appear in the compact notch strip (order matters).
    public static let compactOrder: [SystemMetricKind] = [
        .cpu, .memory, .disk, .network, .battery, .temperature,
    ]

    /// Metrics that can be toggled in Settings (all of them).
    public static let settingsOrder: [SystemMetricKind] = [
        .cpu, .memory, .disk, .network, .battery, .temperature,
        .health, .gpu, .host, .processes,
    ]

    /// Default enabled set.
    public static let defaultEnabled: Set<SystemMetricKind> = [
        .cpu, .memory, .disk, .network, .health, .gpu, .host, .processes, .temperature, .battery,
    ]

    public static func preferenceKey(_ kind: SystemMetricKind) -> String {
        "VoidNotch.systemMetric.\(kind.rawValue).enabled"
    }
}

/// Read/write system metric visibility from UserDefaults (UI-free).
public enum SystemMetricPreferences {
    public static func isEnabled(_ kind: SystemMetricKind, defaults: UserDefaults = .standard) -> Bool {
        let key = SystemMetricKind.preferenceKey(kind)
        if defaults.object(forKey: key) == nil {
            return SystemMetricKind.defaultEnabled.contains(kind)
        }
        return defaults.bool(forKey: key)
    }

    public static func setEnabled(_ kind: SystemMetricKind, _ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: SystemMetricKind.preferenceKey(kind))
    }

    /// Ensure at least one compact metric stays on when turning off.
    public static func canDisable(_ kind: SystemMetricKind, defaults: UserDefaults = .standard) -> Bool {
        let enabledCompact = SystemMetricKind.compactOrder.filter { isEnabled($0, defaults: defaults) }
        if enabledCompact.count <= 1, enabledCompact.contains(kind) {
            return false
        }
        return true
    }

    public static func enabledCompactMetrics(defaults: UserDefaults = .standard) -> [SystemMetricKind] {
        SystemMetricKind.compactOrder.filter { isEnabled($0, defaults: defaults) }
    }

    public static func registerDefaults(_ defaults: UserDefaults = .standard) {
        var dict: [String: Any] = [:]
        for kind in SystemMetricKind.allCases {
            dict[SystemMetricKind.preferenceKey(kind)] = SystemMetricKind.defaultEnabled.contains(kind)
        }
        defaults.register(defaults: dict)
    }
}
