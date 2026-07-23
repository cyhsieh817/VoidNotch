import Observation
import SwiftUI
import VoidNotchKit

struct NotchLayoutSettingsPanel: View {
    let l10n: L10n
    @Bindable var registry: WidgetRegistry
    @Binding var keepLeftOpen: Bool
    @Binding var keepRightOpen: Bool
    let compactProviderChoices: [TokenProviderKind]
    @Binding var compactDisplayProvider: TokenProviderKind?

    private var layout: NotchCompactLayoutStore { registry.layout }

    var body: some View {
        let _ = layout.revision
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(l10n.compactRowTitle, systemImage: "rectangle.compress.vertical")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text(l10n.compactLayoutHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 16) {
                CompactSideEditor(
                    l10n: l10n,
                    side: .leading,
                    title: l10n.leftSide,
                    isOpen: $keepLeftOpen,
                    registry: registry)

                CompactSideEditor(
                    l10n: l10n,
                    side: .trailing,
                    title: l10n.rightSide,
                    isOpen: $keepRightOpen,
                    registry: registry)
            }

            HStack(spacing: 16) {
                HStack(spacing: 12) {
                    Text(l10n.compactHeight)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { Double(layout.contentHeight) },
                            set: { layout.setContentHeight(CGFloat($0)) }),
                        in: Double(NotchCompactLayout.minHeight)...Double(NotchCompactLayout.maxHeight),
                        step: 1)

                    Text("\(Int(layout.contentHeight.rounded())) pt")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    Text(l10n.aiMetric)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Picker("AI metric", selection: $compactDisplayProvider) {
                        Text(l10n.autoOption).tag(Optional<TokenProviderKind>.none)
                        ForEach(compactProviderChoices) { provider in
                            Text(provider.displayName).tag(Optional(provider))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(l10n.aiMetricHelp)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 14)
        .onChange(of: keepLeftOpen) { _, open in
            layout.setPinned(open, side: .leading)
        }
        .onChange(of: keepRightOpen) { _, open in
            layout.setPinned(open, side: .trailing)
        }
        .onAppear {
            // Sync AppStorage toggles with store defaults once.
            keepLeftOpen = layout.isPinned(.leading)
            keepRightOpen = layout.isPinned(.trailing)
        }
    }
}

struct CompactSideEditor: View {
    let l10n: L10n
    let side: NotchSide
    let title: String
    @Binding var isOpen: Bool
    @Bindable var registry: WidgetRegistry

    private var layout: NotchCompactLayoutStore { registry.layout }

    var body: some View {
        let _ = layout.revision
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: $isOpen) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.checkbox)
                .help(isOpen ? l10n.sidePinnedHelp(title) : l10n.sideCollapsedHelp(title))

                Spacer()
                Text("\(Int(layout.maxWidth(for: side).rounded())) pt")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(layout.maxWidth(for: side)) },
                    set: { layout.setMaxWidth(CGFloat($0), for: side) }),
                in: Double(NotchCompactLayout.minWidth)...Double(NotchCompactLayout.maxWidth),
                step: 2)
            .disabled(!isOpen)
            .opacity(isOpen ? 1 : 0.45)

            Text(l10n.sideContent)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(registry.sortedByPriority, id: \.id) { widget in
                    let onSide = layout.isWidget(widget.id, on: side)
                    Toggle(isOn: Binding(
                        get: { onSide },
                        set: { layout.setWidget(widget.id, on: side, enabled: $0) }))
                    {
                        HStack(spacing: 5) {
                            Image(systemName: widget.settingsIconSystemName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(widget.settingsTitle)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .help(widget.settingsSubtitle)
                }
            }
            .disabled(!isOpen)
            .opacity(isOpen ? 1 : 0.45)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }
}
