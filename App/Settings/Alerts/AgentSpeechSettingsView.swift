//
//  AgentSpeechSettingsView.swift — Agent 完成事件 TTS 設定
//

import AVFoundation
import SwiftUI
import VoidNotchKit

struct AgentSpeechSettingsView: View {
    let l10n: L10n
    let onPreviewSpeech: (AgentSpeechLanguage) -> Void

    @AppStorage(AgentSpeechPreferences.Keys.enabled) private var isEnabled = false
    @AppStorage(AgentSpeechPreferences.Keys.completed) private var speakCompleted = true
    @AppStorage(AgentSpeechPreferences.Keys.needsInput) private var speakNeedsInput = false
    @AppStorage(AgentSpeechPreferences.Keys.failed) private var speakFailed = false
    @AppStorage(AgentSpeechPreferences.Keys.resourceLimit) private var speakResourceLimit = false
    @AppStorage(AgentSpeechPreferences.Keys.chineseVoiceIdentifier) private var chineseVoiceIdentifier = ""
    @AppStorage(AgentSpeechPreferences.Keys.englishVoiceIdentifier) private var englishVoiceIdentifier = ""
    @AppStorage(AgentSpeechPreferences.Keys.rate) private var rate = AgentSpeechPreferences.defaultRate

    var body: some View {
        VStack(spacing: 0) {
            enableRow
            Divider()
            eventToggleRow(title: l10n.agentSpeechEnabled, isOn: $speakCompleted)
            eventToggleRow(title: l10n.agentSpeechNeedsInput, isOn: $speakNeedsInput)
            eventToggleRow(title: l10n.agentSpeechFailed, isOn: $speakFailed)
            eventToggleRow(title: l10n.agentSpeechResourceLimit, isOn: $speakResourceLimit)
            Divider()
            voiceRow(
                title: l10n.agentSpeechChineseVoice,
                selection: $chineseVoiceIdentifier,
                language: .zhTW,
                voices: voices(prefix: "zh"))
            Divider().padding(.leading, 50)
            voiceRow(
                title: l10n.agentSpeechEnglishVoice,
                selection: $englishVoiceIdentifier,
                language: .enUS,
                voices: voices(prefix: "en"))
            Divider()
            rateRow
#if DEBUG
            Divider()
            AgentSpeechDebugInputTestCard()
#endif
        }
    }

    private func eventToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
    }

    private var enableRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble.fill")
                .foregroundStyle(.teal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.agentSpeechTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(l10n.agentSpeechEnableHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle(l10n.agentSpeechEnable, isOn: $isEnabled)
                .labelsHidden()
                .accessibilityLabel(l10n.agentSpeechEnable)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func voiceRow(
        title: String,
        selection: Binding<String>,
        language: AgentSpeechLanguage,
        voices: [AVSpeechSynthesisVoice]
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(title, selection: selection) {
                Text(l10n.agentSpeechVoiceSystemDefault).tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text(voiceDisplayName(voice)).tag(voice.identifier)
                }
                if let orphan = orphanSelection(selection.wrappedValue, in: voices) {
                    Text(orphan).tag(orphan)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 178)
            .accessibilityLabel(title)

            Button {
                onPreviewSpeech(language)
            } label: {
                Label(l10n.agentSpeechPreview, systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help(l10n.agentSpeechPreview)
            .accessibilityLabel(l10n.agentSpeechPreview)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var rateRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(l10n.agentSpeechRate)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 72, alignment: .leading)

            Slider(
                value: rateBinding,
                in: AgentSpeechPreferences.minimumRate...AgentSpeechPreferences.maximumRate)
            .accessibilityLabel(l10n.agentSpeechRate)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var rateBinding: Binding<Double> {
        Binding(
            get: { AgentSpeechPreferences.clampedRate(rate) },
            set: { rate = AgentSpeechPreferences.clampedRate($0) })
    }

    private func voices(prefix: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(prefix) }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// 已儲存但目前系統找不到的 identifier 仍掛進 Picker，避免 selection 落空。
    private func orphanSelection(
        _ identifier: String,
        in voices: [AVSpeechSynthesisVoice]
    ) -> String? {
        guard !identifier.isEmpty,
              !voices.contains(where: { $0.identifier == identifier })
        else { return nil }
        return identifier
    }

    private func voiceDisplayName(_ voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) (\(voice.language))"
    }
}

#if DEBUG
/// Settings > Alerts > Speech 底部的編譯期 DEBUG 隔離卡：演練真實麥克風與選項比對，不碰 broker／response／事件檔。
private struct AgentSpeechDebugInputTestCard: View {
    @State private var speechRecognizer = AgentOptionSpeechRecognizer()
    /// 每個卡片 session 固定；Reset 時換新，並以 `.id` 重建 `NotchAgentAlertView` 內部 sent／selections。
    @State private var sessionID = UUID()
    @State private var lastResultText: String?

    private var debugEvent: AgentActivityEvent {
        Self.makeEvent(sessionID: sessionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "mic.badge.xmark")
                    .foregroundStyle(.orange)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DEBUG 語音輸入隔離測試")
                        .font(.system(size: 12, weight: .semibold))
                    Text("真實麥克風與選項比對 · 僅記憶體 · 不寫入事件或 response")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Reset") { reset() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Reset DEBUG speech input test")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            NotchAgentAlertView(
                event: debugEvent,
                topInset: 0,
                onSubmit: { request, selections in
                    lastResultText = Self.formatResult(request: request, selections: selections)
                    return nil
                },
                speechRecognizer: speechRecognizer,
                onSpeechStart: {},
                onFrameChange: { _ in })
            .id(sessionID)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)

            if let lastResultText {
                Text(lastResultText)
                    .font(.system(size: 11, weight: .medium).monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 18)
            }

            Color.clear.frame(height: 4)
                .padding(.bottom, 8)
        }
        .onDisappear {
            speechRecognizer.cancel()
        }
    }

    private func reset() {
        speechRecognizer.cancel()
        lastResultText = nil
        sessionID = UUID()
    }

    private static func makeEvent(sessionID: UUID) -> AgentActivityEvent {
        AgentActivityEvent(
            id: sessionID,
            provider: .codex,
            status: .needsInput,
            title: "DEBUG 語音輸入隔離測試",
            detail: "in-memory isolation",
            workspace: "DEBUG",
            occurredAt: Date(timeIntervalSince1970: 0),
            durationSeconds: nil,
            inputRequest: AgentInputRequest(
                requestID: sessionID,
                questions: [
                    AgentInputQuestion(
                        question: "你要測試哪一種輸入方式？",
                        header: "中文題",
                        options: [
                            AgentInputOption(label: "語音", description: "說出選項標籤"),
                            AgentInputOption(label: "點選", description: "用滑鼠點選"),
                        ],
                        multiSelect: false),
                    AgentInputQuestion(
                        question: "Which option should the microphone match?",
                        header: "English",
                        options: [
                            AgentInputOption(label: "Accept", description: "Positive choice"),
                            AgentInputOption(label: "Reject", description: "Negative choice"),
                        ],
                        multiSelect: false),
                ]))
    }

    private static func formatResult(
        request: AgentInputRequest,
        selections: [Int: Set<String>]
    ) -> String {
        let parts = request.questions.enumerated().map { index, question in
            let chosen = (selections[index] ?? []).sorted().joined(separator: ",")
            let label = chosen.isEmpty ? "—" : chosen
            return "Q\(index + 1)[\(question.header)]: \(label)"
        }
        return "Local result · \(parts.joined(separator: " · "))"
    }
}
#endif
