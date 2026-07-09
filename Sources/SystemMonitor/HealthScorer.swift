//
//  HealthScorer.swift — composite 0–100 health score (concept-aligned with Mole status)
//
//  Pure function; unit-testable. Weights are VoidNotch constants (not copied from Mole code).
//

import Foundation

public enum HealthScorer {
    // Weights
    private static let cpuWeight = 30.0
    private static let memWeight = 25.0
    private static let diskWeight = 20.0
    private static let thermalWeight = 15.0
    private static let ioWeight = 10.0

    // Thresholds
    private static let cpuNormal = 50.0
    private static let cpuHigh = 85.0
    private static let memNormal = 70.0
    private static let memHigh = 88.0
    private static let diskWarn = 80.0
    private static let diskCrit = 93.0
    private static let thermalNormal = 65.0
    private static let thermalHigh = 85.0
    private static let ioNormal = 50.0 // MB/s combined
    private static let ioHigh = 150.0

    public static func score(
        cpuPercent: Double,
        memoryPercent: Double,
        memoryPressure: MemoryPressure,
        diskUsedPercent: Double,
        diskIOMBps: Double,
        cpuTempC: Double?,
        battery: BatteryStatus,
        uptimeSeconds: UInt64) -> HealthScore
    {
        var score = 100.0
        var issues: [String] = []

        // CPU
        if cpuPercent > cpuNormal {
            if cpuPercent > cpuHigh {
                score -= cpuWeight * (cpuPercent - cpuNormal) / cpuHigh
            } else {
                score -= (cpuWeight / 2) * (cpuPercent - cpuNormal) / (cpuHigh - cpuNormal)
            }
            if cpuPercent > cpuHigh { issues.append("High CPU") }
        }

        // Memory
        if memoryPercent > memNormal {
            if memoryPercent > memHigh {
                score -= memWeight * (memoryPercent - memNormal) / memNormal
            } else {
                score -= (memWeight / 2) * (memoryPercent - memNormal) / (memHigh - memNormal)
            }
            if memoryPercent > memHigh { issues.append("High Memory") }
        }
        switch memoryPressure {
        case .warning:
            score -= 5
            issues.append("Memory Pressure")
        case .critical:
            score -= 15
            issues.append("Critical Memory")
        case .normal, .unknown:
            break
        }

        // Disk
        if diskUsedPercent > diskWarn {
            if diskUsedPercent > diskCrit {
                score -= diskWeight * (diskUsedPercent - diskWarn) / (100 - diskWarn)
                issues.append("Disk Almost Full")
            } else {
                score -= (diskWeight / 2) * (diskUsedPercent - diskWarn) / (diskCrit - diskWarn)
            }
        }

        // Thermal (skip when nil)
        if let temp = cpuTempC, temp > 0 {
            if temp > thermalNormal {
                if temp > thermalHigh {
                    score -= thermalWeight
                    issues.append("Overheating")
                } else {
                    score -= thermalWeight * (temp - thermalNormal) / (thermalHigh - thermalNormal)
                }
            }
        }

        // Disk I/O
        if diskIOMBps > ioNormal {
            if diskIOMBps > ioHigh {
                score -= ioWeight
                issues.append("Heavy Disk IO")
            } else {
                score -= ioWeight * (diskIOMBps - ioNormal) / (ioHigh - ioNormal)
            }
        }

        // Battery extras
        if battery.isPresent {
            let label = battery.healthLabel ?? BatteryReader.healthLabel(
                cycles: battery.cycleCount,
                capacity: battery.maxCapacityPercent)
            if label == "Service Soon" {
                score -= 5
                issues.append("Battery Service Soon")
            } else if label == "Fair" {
                score -= 2
            }
        }

        // Long uptime
        if uptimeSeconds > 14 * 86_400 {
            score -= 3
            issues.append("Restart Recommended")
        } else if uptimeSeconds > 7 * 86_400 {
            score -= 1
        }

        let clamped = Int(min(100, max(0, score)).rounded())
        let label: String
        switch clamped {
        case 85...100: label = "Excellent"
        case 65..<85: label = "Good"
        case 45..<65: label = "Fair"
        default: label = "Needs Attention"
        }
        return HealthScore(score: clamped, label: label, issues: issues)
    }
}
