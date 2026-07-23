//
//  AlertSoundSettingsView.swift — Per-event alert sound choices
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoidNotchKit

struct AlertSoundSettingsView: View {
    let l10n: L10n
    @Binding var isEnabled: Bool
    let onPreviewSound: (AlertSoundCategory) -> Void

    private let preferences: AlertSoundPreferences
    @State private var selections: [AlertSoundCategory: AlertSoundSelection]

    init(
        l10n: L10n,
        isEnabled: Binding<Bool>,
        preferences: AlertSoundPreferences = AlertSoundPreferences(),
        onPreviewSound: @escaping (AlertSoundCategory) -> Void
    ) {
        self.l10n = l10n
        _isEnabled = isEnabled
        self.preferences = preferences
        self.onPreviewSound = onPreviewSound
        _selections = State(initialValue: Dictionary(uniqueKeysWithValues:
            AlertSoundCategory.allCases.map { ($0, preferences.selection(for: $0)) }))
    }

    var body: some View {
        VStack(spacing: 0) {
            PeonAudioSettingsRow(l10n: l10n, isEnabled: $isEnabled)
            Divider()

            VStack(spacing: 0) {
                ForEach(Array(AlertSoundCategory.allCases.enumerated()), id: \.element) { index, category in
                    soundRow(category)
                    if index < AlertSoundCategory.allCases.count - 1 {
                        Divider().padding(.leading, 50)
                    }
                }
            }
        }
    }

    private func soundRow(_ category: AlertSoundCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: category))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.alertSoundCategoryTitle(category))
                    .font(.system(size: 12, weight: .semibold))
                Text(l10n.alertSoundCurrentSource(selection(for: category)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker(
                l10n.alertSoundSourcePickerLabel,
                selection: optionBinding(for: category)
            ) {
                Text(l10n.alertSoundSourceSoundPack).tag(SourceOption.soundPack)
                ForEach(AlertSoundPreferences.systemSoundNames, id: \.self) { name in
                    Text(l10n.alertSoundSystemOption(name)).tag(SourceOption.system(name))
                }
                if case let .localFile(path) = option(for: category) {
                    Text(l10n.alertSoundLocalOption(URL(fileURLWithPath: path).lastPathComponent))
                        .tag(SourceOption.localFile(path))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 178)
            .help(l10n.alertSoundSourcePickerHelp)
            .accessibilityLabel(l10n.alertSoundSourcePickerLabel)

            Button {
                chooseLocalFile(for: category)
            } label: {
                Label(l10n.alertSoundChooseFile, systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help(l10n.alertSoundChooseFileHelp)
            .accessibilityLabel(l10n.alertSoundChooseFile)

            Button {
                onPreviewSound(category)
            } label: {
                Label(l10n.alertSoundPreview, systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help(l10n.alertSoundPreviewHelp)
            .accessibilityLabel(l10n.alertSoundPreview)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func selection(for category: AlertSoundCategory) -> AlertSoundSelection {
        selections[category] ?? .soundPack
    }

    private func option(for category: AlertSoundCategory) -> SourceOption {
        let selection = selection(for: category)
        switch selection.kind {
        case .soundPack: return .soundPack
        case .system: return .system(selection.value ?? "")
        case .localFile: return .localFile(selection.value ?? "")
        }
    }

    private func optionBinding(for category: AlertSoundCategory) -> Binding<SourceOption> {
        Binding(
            get: { option(for: category) },
            set: { newValue in
                let selection: AlertSoundSelection
                switch newValue {
                case .soundPack:
                    selection = .soundPack
                case let .system(name):
                    selection = AlertSoundSelection(kind: .system, value: name)
                case let .localFile(path):
                    selection = AlertSoundSelection(kind: .localFile, value: path)
                }
                persist(selection, for: category)
            })
    }

    private func persist(_ selection: AlertSoundSelection, for category: AlertSoundCategory) {
        preferences.setSelection(selection, for: category)
        selections[category] = selection
    }

    private func chooseLocalFile(for category: AlertSoundCategory) {
        let panel = NSOpenPanel()
        panel.title = l10n.alertSoundFilePanelTitle
        panel.prompt = l10n.alertSoundFilePanelPrompt
        panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let path = panel.url?.path,
              preferences.resolvedLocalFileURL(from: path) != nil
        else { return }

        persist(AlertSoundSelection(kind: .localFile, value: path), for: category)
    }

    private func iconName(for category: AlertSoundCategory) -> String {
        switch category {
        case .sessionStart: return "play.circle"
        case .taskComplete: return "checkmark.circle"
        case .inputRequired: return "questionmark.circle"
        case .taskError: return "exclamationmark.triangle"
        case .resourceLimit: return "gauge.with.dots.needle.33percent"
        }
    }

    private enum SourceOption: Hashable {
        case soundPack
        case system(String)
        case localFile(String)
    }
}
