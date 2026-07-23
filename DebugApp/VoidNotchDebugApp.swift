//
//  VoidNotchDebugApp.swift — isolated bilingual microphone companion
//

import SwiftUI
import VoidNotchSpeechKit

@main
struct VoidNotchDebugApp: App {
    var body: some Scene {
        WindowGroup("VoidNotch Debug") {
            DebugContentView()
        }
        .defaultSize(width: 560, height: 680)
        .windowResizability(.contentSize)
    }
}

private enum SpeechTest: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return "中文選項辨識"
        case .english: return "English option recognition"
        }
    }

    var question: AgentInputQuestion {
        switch self {
        case .chinese:
            return AgentInputQuestion(
                question: "你要測試哪一種輸入方式？",
                header: "中文選項",
                options: [
                    AgentInputOption(label: "語音", description: "說出選項標籤"),
                    AgentInputOption(label: "點選", description: "用滑鼠點選"),
                ],
                multiSelect: false)
        case .english:
            return AgentInputQuestion(
                question: "Which option should the microphone match?",
                header: "English options",
                options: [
                    AgentInputOption(label: "Accept", description: "Positive choice"),
                    AgentInputOption(label: "Reject", description: "Negative choice"),
                ],
                multiSelect: false)
        }
    }

    var idleFeedback: String {
        switch self {
        case .chinese: return "按下麥克風，說出一個中文選項。"
        case .english: return "Press the microphone and say one English option."
        }
    }

    var listeningFeedback: String {
        switch self {
        case .chinese: return "聆聽中⋯請說出「語音」或「點選」。"
        case .english: return "Listening… say “Accept” or “Reject”."
        }
    }

    func matchedFeedback(_ label: String) -> String {
        switch self {
        case .chinese: return "已選取：" + label
        case .english: return "Selected: " + label
        }
    }

    func failureFeedback(_ failure: AgentOptionSpeechRecognitionFailure) -> String {
        switch (self, failure) {
        case (.chinese, .permissionDenied): return "需要麥克風與語音辨識權限。"
        case (.english, .permissionDenied): return "Microphone and speech-recognition permission are required."
        case (.chinese, .unavailable): return "目前無法使用語音辨識，請再試一次。"
        case (.english, .unavailable): return "Speech recognition is currently unavailable. Try again."
        case (.chinese, .noMatch): return "語音未能對應到唯一選項，請再試一次。"
        case (.english, .noMatch): return "Speech did not match one unique option. Try again."
        }
    }
}

@MainActor
private struct DebugContentView: View {
    @State private var speechRecognizer = AgentOptionSpeechRecognizer()
    @State private var activeTest: SpeechTest?
    @State private var chineseSelection = ""
    @State private var englishSelection = ""
    @State private var feedbackText = "Ready. Choose a test and use its microphone."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("VoidNotch Debug Companion", systemImage: "waveform.and.mic")
                        .font(.title2.weight(.semibold))
                    Text("Safe isolated microphone testing for the shared Chinese and English option recognizer.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This window keeps selections in local view state and does not submit an answer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SpeechTestCard(
                    test: .chinese,
                    question: SpeechTest.chinese.question,
                    selection: $chineseSelection,
                    activeTest: activeTest,
                    onMicrophone: { toggle(.chinese) })

                SpeechTestCard(
                    test: .english,
                    question: SpeechTest.english.question,
                    selection: $englishSelection,
                    activeTest: activeTest,
                    onMicrophone: { toggle(.english) })

                VStack(alignment: .leading, spacing: 8) {
                    Text("Feedback")
                        .font(.headline)
                    Text(feedbackText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }

                HStack {
                    Spacer()
                    Button("Reset") { reset() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 560)
        .onDisappear {
            speechRecognizer.cancel()
        }
    }

    private func toggle(_ test: SpeechTest) {
        if activeTest == test {
            speechRecognizer.cancel()
            activeTest = nil
            feedbackText = test.idleFeedback
            return
        }

        speechRecognizer.cancel()
        activeTest = test
        feedbackText = test.listeningFeedback
        speechRecognizer.start(
            question: test.question,
            onMatch: { label in
                if test == .chinese {
                    chineseSelection = label
                } else {
                    englishSelection = label
                }
                activeTest = nil
                feedbackText = test.matchedFeedback(label)
            },
            onFailure: { failure in
                activeTest = nil
                feedbackText = test.failureFeedback(failure)
            })
    }

    private func reset() {
        speechRecognizer.cancel()
        activeTest = nil
        chineseSelection = ""
        englishSelection = ""
        feedbackText = "Ready. Choose a test and use its microphone."
    }
}

@MainActor
private struct SpeechTestCard: View {
    let test: SpeechTest
    let question: AgentInputQuestion
    @Binding var selection: String
    let activeTest: SpeechTest?
    let onMicrophone: () -> Void

    private var listening: Bool { activeTest == test }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(test.title)
                        .font(.headline)
                    Text(question.question)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onMicrophone) {
                    Label(
                        listening ? "Stop" : "Microphone",
                        systemImage: listening ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(listening ? .orange : .accentColor)
                .accessibilityLabel(listening ? "Stop microphone" : "Use microphone")
            }

            VStack(spacing: 6) {
                ForEach(question.options, id: \.label) { option in
                    Button {
                        selection = option.label
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selection == option.label
                                ? "checkmark.circle.fill"
                                : "circle")
                                .foregroundStyle(selection == option.label ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .fontWeight(.medium)
                                Text(option.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }

            Text(selection.isEmpty ? "No local selection" : "Local selection: \(selection)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}
