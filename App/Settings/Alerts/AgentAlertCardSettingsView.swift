//
//  AgentAlertCardSettingsView.swift — 問答卡系統通知鏡像 + 字級倍率設定
//

import SwiftUI
import VoidNotchKit

struct AgentAlertCardSettingsView: View {
    let l10n: L10n

    @AppStorage(AgentAlertCardPreferences.Keys.notificationMirror) private var notificationMirrorEnabled = false
    @AppStorage(AgentAlertCardPreferences.Keys.textScale) private var textScaleRaw = AgentAlertCardPreferences.defaultTextScale

    var body: some View {
        VStack(spacing: 0) {
            notificationMirrorRow
            Divider()
            textScaleRow
        }
    }

    private var notificationMirrorRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.teal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.agentAlertNotificationMirrorTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(l10n.agentAlertNotificationMirrorHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(l10n.agentAlertNotificationMirrorTitle, isOn: notificationMirrorBinding)
                .labelsHidden()
                .accessibilityLabel(l10n.agentAlertNotificationMirrorTitle)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// 開關「打開」的那一刻才請求系統授權（不是每次要發通知才問）；關閉不需要動作，
    /// 授權狀態本身仍完全由系統管理，這裡只負責觸發「問一次」的時機。
    private var notificationMirrorBinding: Binding<Bool> {
        Binding(
            get: { notificationMirrorEnabled },
            set: { newValue in
                notificationMirrorEnabled = newValue
                if newValue {
                    AgentAlertNotificationMirror.shared.requestAuthorizationIfNeeded()
                }
            })
    }

    private var textScaleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "textformat.size")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.agentAlertTextScaleTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(l10n.agentAlertTextScaleHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Picker(l10n.agentAlertTextScaleTitle, selection: textScaleBinding) {
                ForEach(AgentAlertTextScalePreset.allCases, id: \.rawValue) { preset in
                    Text(presetTitle(preset)).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel(l10n.agentAlertTextScaleTitle)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// 儲存值是 clamp 過的 Double；讀回來對應不到任何預設檔位時（例如舊版遺留的自由值）
    /// 一律以最接近的檔位顯示，寫回也一律落在四段檔位上，不會產生第五種孤兒值。
    private var textScaleBinding: Binding<AgentAlertTextScalePreset> {
        Binding(
            get: { nearestPreset(for: AgentAlertCardPreferences.clampedTextScale(textScaleRaw)) },
            set: { textScaleRaw = $0.rawValue })
    }

    private func nearestPreset(for value: Double) -> AgentAlertTextScalePreset {
        AgentAlertTextScalePreset.allCases.min {
            abs($0.rawValue - value) < abs($1.rawValue - value)
        } ?? .standard
    }

    private func presetTitle(_ preset: AgentAlertTextScalePreset) -> String {
        switch preset {
        case .small: return l10n.agentAlertTextScaleSmall
        case .standard: return l10n.agentAlertTextScaleStandard
        case .large: return l10n.agentAlertTextScaleLarge
        case .extraLarge: return l10n.agentAlertTextScaleExtraLarge
        }
    }
}
