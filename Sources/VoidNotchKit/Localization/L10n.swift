//
//  L10n.swift — UI chrome 字串表（zh-TW / EN）
//
//  範圍紀律：只翻 UI 骨架（選單、分頁、標題、設定列、pills）；
//  provider 回傳的資料細節字串（adapter hint、coverage 等）維持英文，住在 VoidNotchKit。
//

import Foundation

public struct L10n {
    public let language: AppLanguage

    public init(_ language: AppLanguage) {
        self.language = language
    }

    public init(rawValue: String) {
        self.init(AppLanguage.resolve(rawValue))
    }

    private func pick(_ zh: String, _ en: String) -> String {
        language == .zhTW ? zh : en
    }

    // MARK: 狀態列選單 / 視窗

    public var menuSettings: String { pick("VoidNotch 設定…", "VoidNotch Settings...") }
    public var menuShowDashboard: String { pick("顯示儀表板", "Show Dashboard") }
    public var menuCollapse: String { pick("收回瀏海", "Collapse to Notch") }
    public var menuRefreshTokens: String { pick("重新整理模型用量", "Refresh Token Usage") }
    public var menuRefreshAgents: String { pick("重新整理 Agent 活動", "Refresh Agent Activity") }
    public var menuQuit: String { pick("結束 VoidNotch", "Quit VoidNotch") }
    public var settingsWindowTitle: String { pick("VoidNotch 設定", "VoidNotch Settings") }

    // MARK: 展開面板分頁

    public var tabSystem: String { pick("系統監控", "System") }
    public var tabToken: String { pick("模型配額", "Model Usage") }
    public var tabAgent: String { pick("Agent 活動", "Agent Activity") }
    public var tabScheduled: String { pick("排程", "Scheduled") }
    public var schedPhaseRun: String { pick("運行", "Run") }
    public var schedPhasePaused: String { pick("暫停", "Pause") }
    public var schedPhaseArchived: String { pick("封存", "Archive") }
    public var schedZombieWarning: String { pick("殭屍：下次登入會復活", "Zombie: will reload at next login") }
    public var schedEmptyRun: String { pick("沒有運行中的排程", "No active schedules") }
    public var schedEmptyPaused: String { pick("沒有暫停的排程", "No paused schedules") }
    public var schedEmptyArchived: String { pick("沒有封存的排程", "No archived schedules") }
    public var schedRefresh: String { pick("重新整理", "Refresh") }
    public var schedRemove: String { pick("移除排程", "Remove") }
    public var schedRemoveSystemDirHint: String {
        pick("系統目錄排程需管理員權限，請以 Finder 或終端機處理", "System-directory jobs require admin rights")
    }
    public func schedRemoveConfirmTitle(_ label: String) -> String {
        pick("移除排程「\(label)」？", "Remove schedule \"\(label)\"?")
    }
    public var schedRemoveConfirmMessage: String {
        pick(
            "VoidNotch 只讀取 launchd 排程，無法辨識此排程由哪個 agent 或軟體建立。移除會停止其排程，並將 plist 改名封存（_DELETE_ 前綴，可於封存分頁回看）。",
            "VoidNotch reads launchd schedules and cannot tell which agent or app created this job. Removing unloads it and archives its plist with a _DELETE_ prefix (visible in the Archive tab).")
    }
    public var schedRemoveConfirm: String { pick("移除並封存", "Remove & Archive") }
    public var commonCancel: String { pick("取消", "Cancel") }
    public func schedRemoveFailed(_ reason: String) -> String {
        pick("移除失敗：\(reason)", "Removal failed: \(reason)")
    }
    public var settingsTabScheduled: String { pick("排程", "Scheduled") }

    // MARK: 系統面板（EN-first; zh-TW filled for existing keys）

    public var systemTitle: String { pick("系統", "System") }
    public var cpu: String { "CPU" }
    public var memory: String { pick("記憶體", "Memory") }
    public var cpuTemp: String { pick("CPU 溫度", "CPU Temp") }
    public var gpuTemp: String { pick("GPU 溫度", "GPU Temp") }
    // New status-monitor keys: EN source of truth (zh mirrors EN until Phase D polish).
    public var usage: String { "Usage" }
    public var used: String { "Used" }
    public var free: String { "Free" }
    public var loadAverage: String { "Load" }
    public var pressure: String { "Pressure" }
    public var swap: String { "Swap" }
    public var disk: String { "Disk" }
    public var diskRead: String { "Read" }
    public var diskWrite: String { "Write" }
    public var network: String { "Network" }
    public var interface: String { "Interface" }
    public var download: String { "Down" }
    public var upload: String { "Up" }
    public var power: String { "Power" }
    public var level: String { "Level" }
    public var status: String { "Status" }
    public var cycles: String { "Cycles" }
    public var health: String { "Health" }
    public var thermalGPU: String { "Thermal / GPU" }
    public var gpu: String { "GPU" }
    public var gpuUtil: String { "GPU Util" }
    public var host: String { "Host" }
    public var model: String { "Model" }
    public var chip: String { "Chip" }
    public var uptime: String { "Uptime" }
    public var os: String { "OS" }
    public var topProcesses: String { "Top processes" }

    // MARK: Token 面板

    public var modelUsageTitle: String { pick("模型用量", "Model Usage") }
    public var notRefreshed: String { pick("尚未更新", "not refreshed") }
    public var waiting: String { pick("等待資料", "Waiting") }
    public var adapterPending: String { pick("Adapter 待接入", "Adapter pending") }
    public var noUsageWindow: String { pick("尚無用量視窗", "No usage window") }
    public func leftPercent(_ value: Int) -> String { pick("剩 \(value)%", "Left \(value)%") }
    public func usedPercent(_ value: Int) -> String { pick("已用 \(value)%", "Used \(value)%") }

    // MARK: Agent 面板

    public var agentActivityTitle: String { pick("Agent 活動", "Agent Activity") }
    public var pillActive: String { pick("進行中", "Active") }
    public var pillAttention: String { pick("待處理", "Attention") }
    public var pillRecent: String { pick("近期", "Recent") }
    public var noAgentEvents: String { pick("沒有 agent 事件", "No agent events") }
    public var relayNotConnected: String { pick("PeonPing relay 未連接", "PeonPing relay not connected") }

    // MARK: 設定視窗

    public var settingsTabLayout: String { pick("版面", "Layout") }
    public var settingsTabSystem: String { pick("系統指標", "System") }
    public var settingsTabProviders: String { pick("AI 用量", "Providers") }
    public var settingsTabAlerts: String { pick("提示", "Alerts") }
    public var providersTitle: String { pick("模型供應商", "Providers") }
    public var metricLabel: String { pick("指標", "Metric") }
    public var refresh: String { pick("重新整理", "Refresh") }
    public var refreshing: String { pick("更新中", "Refreshing") }
    public var languageLabel: String { pick("語言", "Language") }
    public var compactRowTitle: String { pick("Compact 顯示", "Compact layout") }
    public var leftSide: String { pick("左側", "Left") }
    public var rightSide: String { pick("右側", "Right") }
    public var autoOption: String { pick("自動", "Auto") }
    public var widgetsRowTitle: String { pick("小工具", "Widgets") }
    public var peonAudioTitle: String { pick("提醒音效", "Alert sounds") }
    public var peonAudioHint: String {
        pick(
            "控制事件的 sound pack、macOS 系統音效或裝置音訊；若 PeonPing hook 已播音，可關閉以避免雙響。",
            "Control the sound pack, macOS system sound, or device audio used for events. Turn this off if the PeonPing hook already plays audio to avoid duplicates.")
    }
    public var alertSoundSourcePickerLabel: String { pick("音效來源", "Sound source") }
    public var alertSoundSourcePickerHelp: String {
        pick("選擇內建音效包、macOS 系統音效或已選的裝置音訊", "Choose the sound pack, a macOS system sound, or the selected device audio")
    }
    public var alertSoundSourceSoundPack: String { pick("內建音效包", "Sound Pack") }
    public func alertSoundSystemOption(_ name: String) -> String {
        pick("macOS 系統音效 · \(name)", "macOS System · \(name)")
    }
    public func alertSoundLocalOption(_ filename: String) -> String {
        pick("裝置音訊 · \(filename)", "Device Audio · \(filename)")
    }
    public var alertSoundChooseFile: String { pick("選擇裝置音訊", "Choose Device Audio") }
    public var alertSoundChooseFileHelp: String {
        pick("從這台 Mac 選擇音訊檔", "Choose an audio file from this Mac")
    }
    public var alertSoundPreview: String { pick("試聽", "Preview") }
    public var alertSoundPreviewHelp: String {
        pick("試聽此事件目前設定的音效", "Preview the sound selected for this event")
    }
    public var alertSoundFilePanelTitle: String { pick("選擇提醒音效", "Choose Alert Sound") }
    public var alertSoundFilePanelPrompt: String { pick("選擇", "Choose") }
    public var alertSoundUnavailable: String { pick("無法使用", "Unavailable") }

    // MARK: Agent 事件語音朗讀

    public var agentSpeechTitle: String { pick("Agent 事件朗讀", "Agent event speech") }
    public var agentSpeechEnabled: String { pick("朗讀完成事件", "Speak completed events") }
    public var agentSpeechHint: String {
        pick(
            "只朗讀受長度限制的安全事件文案，不含 detail／workspace 路徑。預設關閉。",
            "Speaks length-limited safe event messages — no detail or workspace paths. Off by default.")
    }
    public var agentSpeechChineseVoice: String { pick("中文語音", "Chinese voice") }
    public var agentSpeechEnglishVoice: String { pick("英文語音", "English voice") }
    public var agentSpeechRate: String { pick("語速", "Speech rate") }
    public var agentSpeechSystemVoice: String { pick("系統預設", "System default") }
    public var agentSpeechPreview: String { pick("試聽朗讀", "Preview speech") }
    public var agentSpeechNeedsInput: String { pick("朗讀需要輸入", "Speak input requests") }
    public var agentSpeechFailed: String { pick("朗讀失敗事件", "Speak failed events") }
    public var agentSpeechResourceLimit: String { pick("朗讀資源限制事件", "Speak resource-limit events") }
    public var agentInputTerminalHint: String {
        pick(
            "此提示不可在 VoidNotch 作答，請回 Agent 終端機。",
            "This prompt cannot be answered in VoidNotch. Return to the Agent terminal.")
    }
    public var agentSpeechMicrophone: String { pick("使用麥克風辨識選項", "Use microphone to recognize an option") }
    public var agentSpeechListening: String { pick("聆聽中", "Listening") }
    public var agentSpeechNoMatch: String {
        pick("語音未能對應到唯一選項，請再試一次。", "Speech did not match one unique option. Try again.")
    }
    public var agentSpeechUnavailable: String {
        pick("目前無法使用語音辨識，請再試一次。", "Speech recognition is currently unavailable. Try again.")
    }
    public var agentSpeechPermissionDenied: String {
        pick("需要麥克風與語音辨識權限。", "Microphone and speech-recognition permission are required.")
    }

    public var agentSpeechEnable: String { agentSpeechEnabled }
    public var agentSpeechEnableHint: String { agentSpeechHint }
    public var agentSpeechVoiceSystemDefault: String { agentSpeechSystemVoice }

    public func alertSoundCategoryTitle(_ category: AlertSoundCategory) -> String {
        switch category {
        case .sessionStart: return pick("工作階段開始", "Session Started")
        case .taskComplete: return pick("任務完成", "Task Completed")
        case .inputRequired: return pick("需要輸入", "Input Required")
        case .taskError: return pick("任務錯誤", "Task Error")
        case .resourceLimit: return pick("資源限制", "Resource Limit")
        }
    }

    public func alertSoundCurrentSource(_ selection: AlertSoundSelection) -> String {
        switch selection.kind {
        case .soundPack:
            return alertSoundSourceSoundPack
        case .system:
            guard let name = selection.value, !name.isEmpty else { return alertSoundUnavailable }
            return alertSoundSystemOption(name)
        case .localFile:
            guard let path = selection.value, !path.isEmpty else { return alertSoundUnavailable }
            return alertSoundLocalOption(URL(fileURLWithPath: path).lastPathComponent)
        }
    }
    public var compactLayoutHint: String {
        pick("兩側內容與長寬", "Per-side content & size")
    }
    public var compactHeight: String { pick("高度", "Height") }
    public var sideContent: String { pick("內容", "Content") }
    public var aiMetric: String { pick("AI 指標", "AI metric") }
    public var aiMetricHelp: String {
        pick("選擇 compact AI 摘要顯示的供應商", "Provider shown in the AI compact capsule")
    }
    public var systemMetricsTitle: String { pick("系統指標", "System metrics") }
    public var systemMetricsHint: String {
        pick("選擇 compact / 展開要顯示的指標", "Choose metrics for compact & expanded views")
    }
    public func sidePinnedHelp(_ side: String) -> String {
        pick("\(side) compact 保持顯示", "\(side) compact stays visible")
    }
    public func sideCollapsedHelp(_ side: String) -> String {
        pick("\(side) compact 收進 notch", "\(side) compact collapses into the notch")
    }
    public func needCheck(_ count: Int) -> String { pick("\(count) 個待檢查", "\(count) need check") }
    public var gaugeSettingsTitle: String { pick("浮動儀表", "Floating Gauge") }
    public var gaugeEnableLabel: String { pick("顯示浮動儀表", "Show floating gauge") }
    public var gaugeClickThroughLabel: String { pick("預設穿透滑鼠", "Click-through by default") }
    public var gaugeResetPosition: String { pick("重設位置", "Reset position") }
    public var gaugeSkinLabel: String { pick("外觀", "Appearance") }
    public var gaugeSizeLabel: String { pick("大小", "Size") }
    public var gaugeSizeSmall: String { pick("小", "Small") }
    public var gaugeSizeStandard: String { pick("標準", "Standard") }
    public var gaugeSizeLarge: String { pick("大", "Large") }
    public var gaugeSizeXLarge: String { pick("特大", "Extra Large") }
    public var gaugeMenuItems: String { pick("顯示項目", "Items") }
    public var gaugeClickThrough: String { pick("穿透模式", "Click-through") }
    public var gaugeLockPosition: String { pick("鎖定位置", "Lock position") }
    public var gaugeHide: String { pick("隱藏浮動儀表", "Hide gauge") }
    public var menuToggleGauge: String { pick("顯示/隱藏浮動儀表", "Toggle Floating Gauge") }
    public var menubarItemsTitle: String { pick("選單列項目", "Menu bar items") }
    public var displayItemsHint: String { pick("勾選並拖曳排序", "Toggle and drag to reorder") }
    public func displayItemsCount(_ selected: Int, _ max: Int) -> String { "\(selected)/\(max)" }
    public var displayItemsFull: String {
        pick("已達上限，先取消一項才能再加", "Limit reached — deselect one first")
    }
    public var displayItemsMinimum: String {
        pick("至少需保留一項", "At least one item must stay selected")
    }

    // MARK: 設定視窗子頁籤

    public var layoutTabNotch: String { pick("瀏海", "Notch") }
    public var layoutTabMenubar: String { pick("選單列", "Menu bar") }
    public var layoutTabGauge: String { pick("浮動儀表", "Floating Gauge") }
    public var alertsTabSound: String { pick("音效", "Sound") }
    public var alertsTabSpeech: String { pick("語音", "Speech") }
    public var alertsTabAgentWiring: String { pick("Agent 接線", "Agent Wiring") }
    public var providerTabUsage: String { pick("用量", "Usage") }
    public var providerTabDetails: String { pick("資訊", "Details") }
    public var providerTabAccounts: String { pick("帳號", "Accounts") }
    public var providerAccountsUnsupported: String {
        pick("此供應商不需管理帳號", "This provider has no account management")
    }
    public var providerAccountsUnsupportedHint: String {
        pick(
            "用量直接讀本機 CLI 的設定與快取，不需要在這裡登入或匯入帳號。",
            "Usage is read from the local CLI config and cache. No sign-in or import needed here.")
    }

    // MARK: 選單列模式

    public var menubarModeOff: String { pick("關閉", "Off") }
    public var menubarModeIcon: String { pick("圖示", "Icon") }
    public var menubarModeMetrics: String { pick("指標", "Metrics") }
    public var menubarModeTitle: String { pick("選單列顯示", "Menu bar") }
    public var menubarModeHint: String {
        pick(
            "無瀏海機型可改「指標」在選單列看即時摘要",
            "On non-notch displays, use Metrics for a live menu-bar summary")
    }

    // MARK: Agent hook 接線

    public var hookWiringTitle: String { pick("Agent 提示接線", "Agent Hook Wiring") }
    public var hookWire: String { pick("接線", "Connect") }
    public var hookUnwire: String { pick("解除", "Disconnect") }
    public var hookStatusInstalled: String { pick("已接通", "Connected") }
    public var hookStatusNotInstalled: String { pick("未接通", "Not connected") }
    public var hookStatusAgentAbsent: String { pick("未安裝", "Not installed") }
    public func hookStatusConflict(_ message: String) -> String {
        pick("衝突：\(message)", "Conflict: \(message)")
    }
    public var hookUnwireComingSoon: String {
        pick("解除將於後續版本提供", "Disconnect will be available in a later version")
    }
    public var hookVerifyFailed: String {
        pick(
            "重新偵測後未確認接通（可能相依的 agent 尚未接線）",
            "Not confirmed after re-check (a dependent agent may still be unwired)")
    }
    public func hookPromptBanner(_ pendingCount: Int) -> String {
        pick(
            "⚡ VoidNotch 可接管 \(pendingCount) 個 agent 的語音與動畫提示",
            "⚡ VoidNotch can take over voice and animation alerts for \(pendingCount) agents")
    }
    public var enable: String { pick("啟用", "Enable") }
    public var later: String { pick("稍後", "Later") }
    public var hookInstalledSuffix: String { pick("已接通", "Connected") }
    public var hookInstallFailedFallback: String {
        pick("失敗，已保留原檔", "Failed; original file kept")
    }

    // MARK: Agent 接通診斷區塊

    public var connectionSectionTitle: String { pick("接通狀態", "Connection Status") }
    public func connectionPendingCount(_ count: Int) -> String {
        pick("\(count) 待處理", "\(count) pending")
    }
    public var connectionDetailInstalled: String {
        pick("已接通 · 只顯示活動", "Connected · Activity only")
    }
    public var connectionDetailNotInstalled: String {
        pick("未接通 · 按「接通」寫入 hook 設定", "Not connected · Tap \"Connect\" to write hook config")
    }
    public var connectionDetailAgentAbsent: String { pick("未安裝", "Not installed") }
    public func connectionDetailConflict(_ message: String) -> String {
        pick("需處理 · \(message)", "Needs attention · \(message)")
    }

    // MARK: 更新檢查

    public var updateSectionTitle: String { pick("軟體更新", "Software Update") }
    public func updateAvailable(_ version: String) -> String {
        pick("新版本 v\(version) 可用", "Version \(version) available")
    }
    public func updateUpToDate(_ version: String) -> String {
        pick("已是最新版本（v\(version)）", "Up to date (v\(version))")
    }
    public var updateCheckNow: String { pick("立即檢查", "Check Now") }
    public func updateLastChecked(_ relative: String) -> String {
        pick("上次檢查：\(relative)", "Last checked: \(relative)")
    }
    public var updateDownload: String { pick("前往下載", "Download") }
}
