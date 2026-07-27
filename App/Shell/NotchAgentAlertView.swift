//
//  NotchAgentAlertView.swift
//

import SwiftUI
import AppKit
import VoidNotchKit

struct NotchAgentAlertView: View {
    let event: AgentActivityEvent
    let topInset: CGFloat
    let onSubmit: ((AgentInputRequest, [Int: Set<String>]) -> String?)?
    let speechRecognizer: AgentOptionSpeechRecognizer
    let onSpeechStart: () -> Void
    let onFrameChange: (CGRect?) -> Void
    @State private var selections: [Int: Set<String>] = [:]
    @State private var errorText: String?
    @State private var sent = false
    @State private var listeningQuestionIndex: Int?
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue
    /// 卡片重建時（每次彈出都是新 view instance）才重讀一次，符合「即時生效」需求且不需額外觀察者。
    @AppStorage(AgentAlertCardPreferences.Keys.textScale) private var textScaleRaw = AgentAlertCardPreferences.defaultTextScale
    private var l10n: L10n { L10n(rawValue: languageRaw) }

    private enum Appearance {
        static let iconTintOpacity = 0.18
        static let secondaryTextOpacity = 0.72
        static let tintOverlayOpacity = 0.14
        static let contrastOverlayOpacity = 0.28
        /// SwiftUI `.caption` / `.caption2` 在 macOS 的等值 point size；混用 caption 與
        /// `.system(size:)` 兩套字級系統沒有共同倍率基準，統一先換算成固定 point size 再乘。
        static let captionPointSize: CGFloat = 11
        static let caption2PointSize: CGFloat = 10
    }

    /// 讀取時 clamp 至 0.8...1.6，避免壞值（例如舊版遺留或手動改壞的 UserDefaults）撐爆版面。
    private var textScale: CGFloat {
        CGFloat(AgentAlertCardPreferences.clampedTextScale(textScaleRaw))
    }

    /// 所有寫死字級的唯一入口：`.caption`/`.caption2` 先換算成等值 point size 再呼叫這支。
    private func scaled(_ base: CGFloat) -> CGFloat {
        base * textScale
    }

    private var tint: Color {
        switch event.status {
        case .started: return .blue
        case .completed: return .green
        case .needsInput: return .orange
        case .failed, .resourceLimit: return .red
        case .running, .stopped: return .secondary
        }
    }

    private var symbol: String {
        switch event.status {
        case .started: return "play.fill"
        case .completed: return "checkmark.circle.fill"
        case .needsInput: return "questionmark.bubble.fill"
        case .failed: return "xmark.octagon.fill"
        case .resourceLimit: return "exclamationmark.triangle.fill"
        case .running: return "ellipsis"
        case .stopped: return "stop.fill"
        }
    }

    private var context: String? {
        [event.workspace, event.detail]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }

    private var speechPreferredLanguageCode: String {
        AppLanguage.resolve(languageRaw) == .zhTW ? "zh-TW" : "en-US"
    }

    private var headerAccessibilityLabel: String {
        "\(event.provider.displayName) \(event.status.label): \(event.title)"
    }

    private var headerAccessibilityHint: String {
        event.navigation?.isActionable == true
            ? "Open the recorded source app or terminal"
            : "Source navigation unavailable"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
          alertHeader
          if let request = event.inputRequest {
            if sent {
                Label(l10n.answerSent, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(request.questions.enumerated()), id: \.offset) { index, question in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(question.header)
                                        .font(.system(size: scaled(Appearance.captionPointSize), weight: .bold))
                                        .foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    HStack(spacing: 5) {
                                        Button {
                                            toggleSpeech(question: question, index: index, request: request)
                                        } label: {
                                            Image(systemName: listeningQuestionIndex == index ? "stop.circle.fill" : "mic.circle.fill")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .help(listeningQuestionIndex == index ? l10n.agentSpeechListening : l10n.agentSpeechMicrophone)
                                        .accessibilityLabel(listeningQuestionIndex == index ? l10n.agentSpeechListening : l10n.agentSpeechMicrophone)
                                        Text(speechLanguageLabel(for: question))
                                            .font(.system(size: scaled(Appearance.caption2PointSize), weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel(speechLanguageCode(for: question))
                                    }
                                }
                                Text(question.question)
                                    .font(.system(size: scaled(13), weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(question.options, id: \.label) { option in
                                    Button {
                                        toggle(option.label, question: question, index: index, request: request)
                                    } label: {
                                        HStack {
                                            Image(systemName: selections[index, default: []].contains(option.label) ? "checkmark.circle.fill" : "circle")
                                            VStack(alignment: .leading) {
                                                Text(option.label)
                                                if !option.description.isEmpty {
                                                    Text(option.description)
                                                        .font(.system(size: scaled(Appearance.captionPointSize)))
                                                        .foregroundStyle(.secondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered).controlSize(.small)
                                    .accessibilityLabel("\(question.question): \(option.label)")
                                }
                            }
                        }
                        if request.questions.count > 1 || request.questions.contains(where: \.multiSelect) {
                            Button(l10n.submitAnswer) { submit(request) }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                                .keyboardShortcut(.return, modifiers: .command)
                                .disabled(!isComplete(request))
                        }
                        if let errorText {
                            Text(errorText)
                                .font(.system(size: scaled(Appearance.captionPointSize)))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
          } else if event.status == .needsInput {
            Text(l10n.agentInputTerminalHint)
                .font(.system(size: scaled(Appearance.captionPointSize)))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.top, topInset)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(width: 420, alignment: .leading)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(tint.opacity(Appearance.tintOverlayOpacity))
                Rectangle().fill(Color.black.opacity(Appearance.contrastOverlayOpacity))
                AlertBoundsObserver(onFrameChange: onFrameChange)
            }
        }
        .onDisappear {
            speechRecognizer.cancel()
            listeningQuestionIndex = nil
            onFrameChange(nil)
        }
    }

    @ViewBuilder
    private var alertHeader: some View {
        if event.navigation?.isActionable == true {
            Button {
                AgentActivityNavigation.open(event.navigation)
            } label: {
                headerContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(headerAccessibilityLabel)
            .accessibilityHint(headerAccessibilityHint)
        } else {
            headerContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(headerAccessibilityLabel)
                .accessibilityHint(headerAccessibilityHint)
        }
    }

    private var headerContent: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: scaled(26), weight: .bold))
                .foregroundStyle(tint)
                .frame(width: scaled(42), height: scaled(42))
                .background(tint.opacity(Appearance.iconTintOpacity), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(event.provider.displayName)
                    .font(.system(size: scaled(11), weight: .bold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                Text(event.title)
                    .font(.system(size: scaled(16), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let context {
                    Text(context)
                        .font(.system(size: scaled(11), weight: .medium))
                        .foregroundStyle(.white.opacity(Appearance.secondaryTextOpacity))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ label: String, question: AgentInputQuestion, index: Int, request: AgentInputRequest) {
        speechRecognizer.cancel()
        listeningQuestionIndex = nil
        apply(
            label: label,
            question: question,
            index: index,
            request: request,
            shouldAutoSubmit: !question.multiSelect && request.questions.count == 1)
    }

    private func apply(
        label: String,
        question: AgentInputQuestion,
        index: Int,
        request: AgentInputRequest,
        shouldAutoSubmit: Bool)
    {
        if question.multiSelect {
            var selected = selections[index, default: []]
            if selected.contains(label) { selected.remove(label) } else { selected.insert(label) }
            selections[index] = selected
        } else {
            selections[index] = [label]
        }
        if shouldAutoSubmit, isComplete(request) { submit(request) }
    }

    private func toggleSpeech(question: AgentInputQuestion, index: Int, request: AgentInputRequest) {
        if listeningQuestionIndex == index {
            speechRecognizer.cancel()
            listeningQuestionIndex = nil
            return
        }

        speechRecognizer.cancel()
        onSpeechStart()
        errorText = nil
        listeningQuestionIndex = index
        speechRecognizer.start(
            question: question,
            onMatch: { label in
                guard event.inputRequest?.requestID == request.requestID else { return }
                listeningQuestionIndex = nil
                apply(
                    label: label,
                    question: question,
                    index: index,
                    request: request,
                    shouldAutoSubmit: true)
            },
            onFailure: { reason in
                listeningQuestionIndex = nil
                switch reason {
                case .permissionDenied:
                    errorText = l10n.agentSpeechPermissionDenied
                case .unavailable:
                    errorText = l10n.agentSpeechUnavailable
                case .noMatch:
                    errorText = l10n.agentSpeechNoMatch
                }
            },
            preferredLanguageCode: speechPreferredLanguageCode)
    }

    private func speechLanguageCode(for question: AgentInputQuestion) -> String {
        AgentSpeechOptionMatcher.languageCode(
            question: question.question,
            header: question.header,
            labels: question.options.map(\.label),
            preferredLanguageCode: speechPreferredLanguageCode)
    }

    private func speechLanguageLabel(for question: AgentInputQuestion) -> String {
        speechLanguageCode(for: question) == "zh-TW" ? "中文" : "EN"
    }

    private func isComplete(_ request: AgentInputRequest) -> Bool {
        request.questions.indices.allSatisfy { !(selections[$0] ?? []).isEmpty }
    }

    private func submit(_ request: AgentInputRequest) {
        guard isComplete(request), let onSubmit else { return }
        if let error = onSubmit(request, selections) { errorText = l10n.answerFailed + " " + error }
        else { sent = true; errorText = nil }
    }
}

private struct AlertBoundsObserver: NSViewRepresentable {
    let onFrameChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> BoundsTrackingView {
        BoundsTrackingView(onFrameChange: onFrameChange)
    }

    func updateNSView(_ nsView: BoundsTrackingView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.reportFrame()
    }

    static func dismantleNSView(_ nsView: BoundsTrackingView, coordinator: ()) {
        nsView.onFrameChange(nil)
    }

    @MainActor
    final class BoundsTrackingView: NSView {
        var onFrameChange: (CGRect?) -> Void
        private var lastFrame: CGRect?

        init(onFrameChange: @escaping (CGRect?) -> Void) {
            self.onFrameChange = onFrameChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
        }

        override func layout() {
            super.layout()
            reportFrame()
        }

        func reportFrame() {
            guard let window else {
                publish(nil)
                return
            }
            let frame = window.convertToScreen(convert(bounds, to: nil))
            publish(frame)
        }

        private func publish(_ frame: CGRect?) {
            guard lastFrame != frame else { return }
            lastFrame = frame
            onFrameChange(frame)
        }
    }
}
