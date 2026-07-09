//
//  L10n.swift — UI chrome 字串表（zh-TW / EN）
//
//  範圍紀律：只翻 UI 骨架（選單、分頁、標題、設定列、pills）；
//  provider 回傳的資料細節字串（adapter hint、coverage 等）維持英文，住在 VoidNotchKit。
//

import Foundation
import VoidNotchKit

struct L10n {
    let language: AppLanguage

    init(_ language: AppLanguage) {
        self.language = language
    }

    init(rawValue: String) {
        self.init(AppLanguage.resolve(rawValue))
    }

    private func pick(_ zh: String, _ en: String) -> String {
        language == .zhTW ? zh : en
    }

    // MARK: 狀態列選單 / 視窗

    var menuSettings: String { pick("VoidNotch 設定…", "VoidNotch Settings...") }
    var menuShowDashboard: String { pick("顯示儀表板", "Show Dashboard") }
    var menuCollapse: String { pick("收回瀏海", "Collapse to Notch") }
    var menuRefreshTokens: String { pick("重新整理模型用量", "Refresh Token Usage") }
    var menuRefreshAgents: String { pick("重新整理 Agent 活動", "Refresh Agent Activity") }
    var menuQuit: String { pick("結束 VoidNotch", "Quit VoidNotch") }
    var settingsWindowTitle: String { pick("VoidNotch 設定", "VoidNotch Settings") }

    // MARK: 展開面板分頁

    var tabSystem: String { pick("系統監控", "System") }
    var tabToken: String { pick("模型配額", "Model Usage") }
    var tabAgent: String { pick("Agent 活動", "Agent Activity") }

    // MARK: 系統面板（EN-first; zh-TW filled for existing keys）

    var systemTitle: String { pick("系統", "System") }
    var cpu: String { "CPU" }
    var memory: String { pick("記憶體", "Memory") }
    var cpuTemp: String { pick("CPU 溫度", "CPU Temp") }
    var gpuTemp: String { pick("GPU 溫度", "GPU Temp") }
    // New status-monitor keys: EN source of truth (zh mirrors EN until Phase D polish).
    var usage: String { "Usage" }
    var used: String { "Used" }
    var free: String { "Free" }
    var loadAverage: String { "Load" }
    var pressure: String { "Pressure" }
    var swap: String { "Swap" }
    var disk: String { "Disk" }
    var diskRead: String { "Read" }
    var diskWrite: String { "Write" }
    var network: String { "Network" }
    var interface: String { "Interface" }
    var download: String { "Down" }
    var upload: String { "Up" }
    var power: String { "Power" }
    var level: String { "Level" }
    var status: String { "Status" }
    var cycles: String { "Cycles" }
    var health: String { "Health" }
    var thermalGPU: String { "Thermal / GPU" }
    var gpu: String { "GPU" }
    var gpuUtil: String { "GPU Util" }
    var host: String { "Host" }
    var model: String { "Model" }
    var chip: String { "Chip" }
    var uptime: String { "Uptime" }
    var os: String { "OS" }
    var topProcesses: String { "Top processes" }

    // MARK: Token 面板

    var modelUsageTitle: String { pick("模型用量", "Model Usage") }
    var notRefreshed: String { pick("尚未更新", "not refreshed") }
    var waiting: String { pick("等待資料", "Waiting") }
    var adapterPending: String { pick("Adapter 待接入", "Adapter pending") }
    var noUsageWindow: String { pick("尚無用量視窗", "No usage window") }
    func leftPercent(_ value: Int) -> String { pick("剩 \(value)%", "Left \(value)%") }
    func usedPercent(_ value: Int) -> String { pick("已用 \(value)%", "Used \(value)%") }

    // MARK: Agent 面板

    var agentActivityTitle: String { pick("Agent 活動", "Agent Activity") }
    var pillActive: String { pick("進行中", "Active") }
    var pillAttention: String { pick("待處理", "Attention") }
    var pillRecent: String { pick("近期", "Recent") }
    var noAgentEvents: String { pick("沒有 agent 事件", "No agent events") }
    var relayNotConnected: String { pick("PeonPing relay 未連接", "PeonPing relay not connected") }

    // MARK: 設定視窗

    var providersTitle: String { pick("模型供應商", "Providers") }
    var metricLabel: String { pick("指標", "Metric") }
    var refresh: String { pick("重新整理", "Refresh") }
    var refreshing: String { pick("更新中", "Refreshing") }
    var languageLabel: String { pick("語言", "Language") }
    var compactRowTitle: String { pick("Compact 顯示", "Compact layout") }
    var leftSide: String { pick("左側", "Left") }
    var rightSide: String { pick("右側", "Right") }
    var autoOption: String { pick("自動", "Auto") }
    var widgetsRowTitle: String { pick("小工具", "Widgets") }
    var compactLayoutHint: String {
        pick("兩側內容與長寬", "Per-side content & size")
    }
    var compactHeight: String { pick("高度", "Height") }
    var sideContent: String { pick("內容", "Content") }
    var aiMetric: String { pick("AI 指標", "AI metric") }
    var aiMetricHelp: String {
        pick("選擇 compact AI 摘要顯示的供應商", "Provider shown in the AI compact capsule")
    }
    var systemMetricsTitle: String { pick("系統指標", "System metrics") }
    var systemMetricsHint: String {
        pick("選擇 compact / 展開要顯示的指標", "Choose metrics for compact & expanded views")
    }
    func sidePinnedHelp(_ side: String) -> String {
        pick("\(side) compact 保持顯示", "\(side) compact stays visible")
    }
    func sideCollapsedHelp(_ side: String) -> String {
        pick("\(side) compact 收進 notch", "\(side) compact collapses into the notch")
    }
    func needCheck(_ count: Int) -> String { pick("\(count) 個待檢查", "\(count) need check") }
}
