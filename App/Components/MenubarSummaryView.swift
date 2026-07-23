//
//  MenubarSummaryView.swift — Menubar HUD 活體摘要 + 模式列舉
//
//  metrics 模式：精簡單行 CPU / RAM / AI 用量，可選 agent 活躍點。
//  模式偏好 key：`VoidNotch.menubar.mode`（off / icon / metrics）。
//

import AppKit
import SwiftUI
import SystemMonitor
import VoidNotchKit

// MARK: - Mode

/// 狀態列顯示模式。首次未寫入時依 notch 自動預設（有 notch → icon、無 notch → metrics）。
enum MenubarDisplayMode: String, CaseIterable, Identifiable {
    case off
    case icon
    case metrics

    static let preferenceKey = "VoidNotch.menubar.mode"

    var id: String { rawValue }

    /// 已儲存偏好；若尚未設定則依目前螢幕 notch 自動選預設（不寫回 UserDefaults）。
    static func resolve(
        defaults: UserDefaults = .standard,
        screen: NSScreen? = nil
    ) -> MenubarDisplayMode {
        if let raw = defaults.string(forKey: preferenceKey),
           let mode = MenubarDisplayMode(rawValue: raw)
        {
            return mode
        }
        return autoDefault(screen: screen)
    }

    /// 首次啟動自動預設：有 notch → 劉海負責 HUD（icon）；無 notch → menubar 顯示指標。
    static func autoDefault(screen: NSScreen? = nil) -> MenubarDisplayMode {
        hasNotch(on: screen) ? .icon : .metrics
    }

    /// 以系統 API 判定瀏海（不 hardcode 機型）。
    /// 優先 `safeAreaInsets.top`；輔以 `auxiliaryTopLeft/RightArea`（與 NotchShell 幾何同源）。
    static func hasNotch(on screen: NSScreen? = nil) -> Bool {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let target else { return false }
        if target.safeAreaInsets.top > 0 { return true }
        let left = target.auxiliaryTopLeftArea?.width ?? 0
        let right = target.auxiliaryTopRightArea?.width ?? 0
        return left > 0 || right > 0
    }

    func settingsLabel(language: AppLanguage) -> String {
        let l10n = L10n(language)
        switch self {
        case .off: return l10n.menubarModeOff
        case .icon: return l10n.menubarModeIcon
        case .metrics: return l10n.menubarModeMetrics
        }
    }

    static func settingsTitle(language: AppLanguage) -> String {
        L10n(language).menubarModeTitle
    }

    static func settingsHint(language: AppLanguage) -> String {
        L10n(language).menubarModeHint
    }
}

// MARK: - Live summary view

/// 狀態列 metrics 模式用的精簡單行摘要；消費既有 @Observable store，隨資料更新。
struct MenubarSummaryView: View {
    let systemMonitor: ObservableSystemMonitor
    let tokenStore: TokenStore
    let agentStore: AgentActivityStore

    var body: some View {
        // 沿用 TokenStore 既有輪播間隔，讓 AI 用量與 compact capsule 同步切換。
        TimelineView(.periodic(from: .now, by: TokenStore.compactRotationInterval)) { timeline in
            let items = DisplaySelectionStore.items(for: .menubar)
            let readings = DisplayReadings.make(
                items: items, snapshot: systemMonitor.snapshot,
                tokenStore: tokenStore, agentStore: agentStore, at: timeline.date)
            HStack(spacing: 6) {
                ForEach(Array(zip(items, readings).enumerated()), id: \.offset) { _, pair in
                    menubarCell(item: pair.0, reading: pair.1)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func menubarCell(item: DisplayItem, reading: DisplayReading) -> some View {
        if case .agentActivity = item {
            // 保留現行語意：活躍/待命才亮點，否則整項不佔位
            if agentStore.activeEventCount > 0 || agentStore.attentionEventCount > 0 {
                Circle().fill(reading.tintKey.color).frame(width: 5, height: 5)
            }
        } else {
            Text("\(item.compactLabel) \(reading.text)\(reading.unit)")
                .foregroundStyle(reading.tintKey.color)
        }
    }
}

private extension DisplayItem {
    /// menubar 前綴短標（沿用舊視覺：CPU / RAM / 無前綴 AI）。
    var compactLabel: String {
        switch self {
        case .system(.cpu): return "CPU"
        case .system(.memory): return "RAM"
        case .aiUsage: return ""
        default: return label(language: AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)))
        }
    }
}
