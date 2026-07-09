//
//  Logger.swift — SystemMonitor 統一 logging 入口
//

import OSLog

enum SystemMonitorLog {
    private static let subsystem = "dev.voidnotch"

    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    static let thermal = Logger(subsystem: subsystem, category: "thermal")
}
