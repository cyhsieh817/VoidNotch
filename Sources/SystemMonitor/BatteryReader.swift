//
//  BatteryReader.swift — IOPS + AppleSmartBattery (MIT-style, inspired by Stats)
//

import Foundation
import IOKit
import IOKit.ps

public final class BatteryReader: @unchecked Sendable {
    public init() {}

    public func read() -> BatteryStatus {
        var status = BatteryStatus()
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        guard !list.isEmpty else {
            status.isPresent = false
            return status
        }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey] as? String
            // Internal battery only.
            if let type, type != kIOPSInternalBatteryType { continue }

            status.isPresent = true
            let powerSource = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            status.isPluggedIn = powerSource == kIOPSACPowerValue
            status.isCharging = desc[kIOPSIsChargingKey] as? Bool
                ?? (desc["IsCharging"] as? Bool)
            if let cap = desc[kIOPSCurrentCapacityKey] as? Int {
                status.percent = min(100, max(0, cap))
            }
            if let empty = desc[kIOPSTimeToEmptyKey] as? Int, empty > 0, status.isPluggedIn != true {
                status.timeRemainingMinutes = empty
            } else if let full = desc[kIOPSTimeToFullChargeKey] as? Int, full > 0, status.isCharging == true {
                status.timeRemainingMinutes = full
            }
            break
        }

        if status.isPresent {
            applySmartBattery(&status)
            status.healthLabel = Self.healthLabel(
                cycles: status.cycleCount,
                capacity: status.maxCapacityPercent)
        }
        return status
    }

    private func applySmartBattery(_ status: inout BatteryStatus) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        if let cycles = Self.intProp(service, "CycleCount") {
            status.cycleCount = cycles
        }
        // Apple Silicon: AppleRawMaxCapacity / DesignCapacity → health %.
        let design = Self.intProp(service, "DesignCapacity") ?? 0
        let maxCap = Self.intProp(service, "AppleRawMaxCapacity")
            ?? Self.intProp(service, "MaxCapacity")
            ?? 0
        if design > 0, maxCap > 0 {
            status.maxCapacityPercent = min(100, max(0, Int((Double(maxCap) / Double(design) * 100).rounded())))
        } else if let maxOnly = Self.intProp(service, "MaxCapacity"), maxOnly <= 100 {
            status.maxCapacityPercent = maxOnly
        }
        if status.percent == nil {
            let soc = Self.intProp(service, "CurrentCapacity")
                ?? Self.intProp(service, "AppleRawCurrentCapacity")
            if let soc {
                if design > 0, soc > 100 {
                    status.percent = min(100, max(0, Int((Double(soc) / Double(design) * 100).rounded())))
                } else if soc <= 100 {
                    status.percent = soc
                }
            }
        }
    }

    public static func healthLabel(cycles: Int?, capacity: Int?) -> String {
        let c = cycles ?? 0
        let cap = capacity ?? 100
        if c > 900 || cap < 60 { return "Service Soon" }
        if c > 800 || cap < 80 { return "Fair" }
        return "Healthy"
    }

    private static func intProp(_ service: io_service_t, _ key: String) -> Int? {
        guard let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let n = prop as? NSNumber { return n.intValue }
        if let i = prop as? Int { return i }
        return nil
    }
}
