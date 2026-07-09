//
//  ObservableSystemMonitor.swift — SystemMonitorManager 的 @Observable 包裝
//
//  ⚠️ Xcode app target 專屬。
//  橋接已驗證的純資料層（Sources/SystemMonitor）→ SwiftUI。
//  widget view 訂閱此物件即自動重繪（dynamicnotchkit-spike §3 證明的 live update 姿勢）。
//

import Foundation
import Observation
import SystemMonitor

@Observable
@MainActor
public final class ObservableSystemMonitor {
    public private(set) var snapshot = SystemSnapshot()

    @ObservationIgnored private let manager = SystemMonitorManager()

    public init(snapshot: SystemSnapshot = SystemSnapshot()) {
        self.snapshot = snapshot
    }

    public func start(interval: TimeInterval = 2.0) {
        manager.startPolling(interval: interval) { [weak self] snap in
            Task { @MainActor in
                self?.snapshot = snap
            }
        }
    }

    public func stop() {
        manager.stopPolling()
    }

    func setActivityLevel(_ level: MonitorActivityLevel) {
        manager.updateInterval(SystemMonitorManager.pollingInterval(for: level))
    }
}
