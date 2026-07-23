import SwiftUI
import VoidNotchKit

struct SystemMetricsSettingsRow: View {
    let l10n: L10n
    @State private var revision = 0

    var body: some View {
        let _ = revision
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(l10n.systemMetricsTitle, systemImage: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text(l10n.systemMetricsHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 10)],
                alignment: .leading,
                spacing: 8)
            {
                ForEach(SystemMetricKind.settingsOrder) { kind in
                    Toggle(isOn: Binding(
                        get: { SystemMetricPreferences.isEnabled(kind) },
                        set: { newValue in
                            if !newValue, !SystemMetricPreferences.canDisable(kind) {
                                return
                            }
                            SystemMetricPreferences.setEnabled(kind, newValue)
                            revision += 1
                        }))
                    {
                        HStack(spacing: 5) {
                            Image(systemName: kind.iconSystemName)
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 14)
                            Text(kind.label)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(
                        SystemMetricPreferences.isEnabled(kind)
                            && !SystemMetricPreferences.canDisable(kind))
                    .help(kind.label)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
