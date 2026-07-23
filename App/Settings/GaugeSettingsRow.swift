import SwiftUI
import VoidNotchKit

struct GaugeSettingsRow: View {
    let l10n: L10n
    let onResetPosition: () -> Void
    @AppStorage("VoidNotch.gauge.enabled") private var isEnabled = false
    @AppStorage("VoidNotch.gauge.skin") private var skinID = "seven-segment"
    @AppStorage("VoidNotch.gauge.clickThrough") private var isClickThrough = false
    @AppStorage("VoidNotch.gauge.scale") private var scale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label(l10n.gaugeSettingsTitle, systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))

                Spacer(minLength: 12)

                Toggle(l10n.gaugeEnableLabel, isOn: $isEnabled)
                    .toggleStyle(.checkbox)
            }

            DisplayItemsEditor(surface: .gauge, l10n: l10n)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.gaugeSkinLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                GaugeSkinPicker(skinID: $skinID, language: l10n.language)
            }

            // 大小／穿透／重設位置併成一列。
            HStack(spacing: 16) {
                Text(l10n.gaugeSizeLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("", selection: $scale) {
                    Text(l10n.gaugeSizeSmall).tag(0.8)
                    Text(l10n.gaugeSizeStandard).tag(1.0)
                    Text(l10n.gaugeSizeLarge).tag(1.25)
                    Text(l10n.gaugeSizeXLarge).tag(1.5)
                }
                .labelsHidden()
                .frame(width: 90)

                Divider().frame(height: 18)

                Toggle(l10n.gaugeClickThroughLabel, isOn: $isClickThrough)
                    .toggleStyle(.checkbox)

                Spacer(minLength: 12)

                Button(l10n.gaugeResetPosition) {
                    onResetPosition()
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
