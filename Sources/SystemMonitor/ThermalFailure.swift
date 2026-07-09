//
//  ThermalFailure.swift — 溫度讀取失敗原因
//

/// 溫度讀取是 best-effort；失敗時用此 enum 保留可觀測原因。
public enum ThermalFailure: Int, Sendable, Equatable, CustomStringConvertible {
    case unknown = 0
    case ioHIDClientUnavailable = 1
    case ioHIDServicesUnavailable = 2
    case noTemperatureServices = 3
    case noReadableSensors = 4
    case valueOutOfRange = 5
    case sensorKeyMissing = 6

    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .ioHIDClientUnavailable:
            return "IOHID event system client unavailable"
        case .ioHIDServicesUnavailable:
            return "IOHID temperature services unavailable"
        case .noTemperatureServices:
            return "no temperature services found"
        case .noReadableSensors:
            return "temperature services found, but no readable sensor events"
        case .valueOutOfRange:
            return "temperature readings were outside the accepted range"
        case .sensorKeyMissing:
            return "temperature readings found, but expected CPU/GPU/SOC keys were missing"
        }
    }
}
