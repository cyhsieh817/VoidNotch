import SwiftUI
import VoidNotchKit

struct MenubarModeSettingsRow: View {
    let language: AppLanguage
    /// 空字串 = 尚未手動設定；顯示值走 notch 自動預設，選過後才寫入 key。
    @AppStorage(MenubarDisplayMode.preferenceKey) private var modeRaw = ""

    private var selection: Binding<MenubarDisplayMode> {
        Binding(
            get: {
                MenubarDisplayMode(rawValue: modeRaw) ?? MenubarDisplayMode.autoDefault()
            },
            set: { modeRaw = $0.rawValue })
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "menubar.rectangle")
                .foregroundStyle(.cyan)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(MenubarDisplayMode.settingsTitle(language: language))
                    .font(.system(size: 12, weight: .semibold))
                Text(MenubarDisplayMode.settingsHint(language: language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Picker("", selection: selection) {
                ForEach(MenubarDisplayMode.allCases) { mode in
                    Text(mode.settingsLabel(language: language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct PeonAudioSettingsRow: View {
    let l10n: L10n
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.peonAudioTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(l10n.peonAudioHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
