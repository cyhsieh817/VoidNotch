//
//  ThermalReader.swift — 溫度讀取（IOHID via CSensors）
//
//  Apple Silicon 主路徑：列舉 IOHID 溫度感測器，依名稱前綴彙整：
//    pACC* (效能核) + eACC* (效率核) → CPU 平均
//    GPU*  → GPU 平均
//    SOC*  → SOC 平均
//  目標機型全為有瀏海 Apple Silicon（見 stats-architecture §4.4），故不實作 Intel SMC key 表。
//

import Foundation
import CSensors

public final class ThermalReader {
    public private(set) var lastFailureReason: ThermalFailure?

    public init() {}

    public func read() -> ThermalSnapshot {
        var failureCode: Int = 0
        let sensors = VNReadAppleSiliconTemperaturesWithFailure(&failureCode) // [名稱: 攝氏]
        let temperatures = sensors.reduce(into: [String: Double]()) { result, sensor in
            result[sensor.key] = sensor.value.doubleValue
        }
        let snapshot = thermalSnapshot(from: temperatures)

        if snapshot.cpu != nil || snapshot.gpu != nil || snapshot.soc != nil {
            clearFailureIfRecovered()
        } else if !sensors.isEmpty {
            recordFailure(.sensorKeyMissing)
        } else {
            recordFailure(ThermalFailure(rawValue: failureCode) ?? .unknown)
        }

        return snapshot
    }

    private func recordFailure(_ failure: ThermalFailure) {
        if lastFailureReason != failure {
            SystemMonitorLog.thermal.warning("Thermal unavailable: \(failure.description, privacy: .public)")
        }
        lastFailureReason = failure
    }

    private func clearFailureIfRecovered() {
        if let previous = lastFailureReason {
            SystemMonitorLog.thermal.notice("Thermal recovered after: \(previous.description, privacy: .public)")
        }
        lastFailureReason = nil
    }
}

/// 將 IOHID 感測器依用途分類；CPU 專用鍵缺席時才採用 PMU die 溫度後備。
func thermalSnapshot(from sensors: [String: Double]) -> ThermalSnapshot {
    var cpuVals: [Double] = []
    var cpuFallbackVals: [Double] = []
    var gpuVals: [Double] = []
    var socVals: [Double] = []

    for (name, temp) in sensors {
        if name.hasPrefix("pACC") || name.hasPrefix("eACC") {
            cpuVals.append(temp)
        } else if name.range(of: #"^PMU tdie[0-9]+$"#, options: .regularExpression) == name.startIndex..<name.endIndex {
            cpuFallbackVals.append(temp)
        } else if name.hasPrefix("GPU") {
            gpuVals.append(temp)
        } else if name.hasPrefix("SOC") {
            socVals.append(temp)
        }
    }

    return ThermalSnapshot(
        cpu: (cpuVals.isEmpty ? cpuFallbackVals : cpuVals).average,
        gpu: gpuVals.average,
        soc: socVals.average
    )
}

private extension Array where Element == Double {
    /// 平均；空陣列回 nil。
    var average: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }
}
