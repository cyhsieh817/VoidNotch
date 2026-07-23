import Observation
import SwiftUI
import VoidNotchKit

struct WidgetVisibilitySettingsRow: View {
    let l10n: L10n
    @Bindable var registry: WidgetRegistry

    var body: some View {
        let _ = registry.visibilityRevision
        HStack(spacing: 12) {
            Label(l10n.widgetsRowTitle, systemImage: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Spacer(minLength: 10)

            ForEach(registry.sortedByPriority, id: \.id) { widget in
                WidgetVisibilityToggle(
                    widget: widget,
                    isVisible: Binding(
                        get: { registry.isWidgetVisible(widget) },
                        set: { registry.setWidget(id: widget.id, visible: $0) }),
                    canDisable: registry.canSetWidget(id: widget.id, visible: false))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct WidgetVisibilityToggle: View {
    let widget: any NotchWidget
    @Binding var isVisible: Bool
    let canDisable: Bool

    var body: some View {
        Toggle(isOn: $isVisible) {
            HStack(spacing: 5) {
                Image(systemName: widget.settingsIconSystemName)
                    .font(.system(size: 10, weight: .semibold))
                Text(widget.settingsTitle)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isVisible && !canDisable)
        .help(widget.settingsSubtitle)
    }
}
