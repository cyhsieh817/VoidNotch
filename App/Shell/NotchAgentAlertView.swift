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
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue
    private var l10n: L10n { L10n(rawValue: languageRaw) }

    private enum Appearance {
        static let iconTintOpacity = 0.18
        static let secondaryTextOpacity = 0.72
        static let tintOverlayOpacity = 0.14
        static let contrastOverlayOpacity = 0.28
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
          if event.status == .needsInput {
            Text(l10n.agentInputTerminalHint)
                .font(.caption)
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
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(Appearance.iconTintOpacity), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(event.provider.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let context {
                    Text(context)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(Appearance.secondaryTextOpacity))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
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
