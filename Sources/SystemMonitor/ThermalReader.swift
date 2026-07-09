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

        var cpuVals: [Double] = []
        var gpuVals: [Double] = []
        var socVals: [Double] = []

        for (name, value) in sensors {
            let temp = value.doubleValue
            if name.hasPrefix("pACC") || name.hasPrefix("eACC") {
                cpuVals.append(temp)
            } else if name.hasPrefix("GPU") {
                gpuVals.append(temp)
            } else if name.hasPrefix("SOC") {
                socVals.append(temp)
            }
        }

        let snapshot = ThermalSnapshot(
            cpu: cpuVals.average,
            gpu: gpuVals.average,
            soc: socVals.average
        )

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

private extension Array where Element == Double {
    /// 平均；空陣列回 nil。
    var average: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }
}
