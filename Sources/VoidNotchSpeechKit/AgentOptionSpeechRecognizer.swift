//
//  AgentOptionSpeechRecognizer.swift — isolated option speech recognition
//

import AVFoundation
import Speech

/// 每次按下題目卡的麥克風才啟動；辨識結果只能回傳既有 option label。
public enum AgentOptionSpeechRecognitionFailure {
    case permissionDenied
    case unavailable
    case noMatch
}

@MainActor
public final class AgentOptionSpeechRecognizer: NSObject, SFSpeechRecognizerDelegate {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var tapInstalled = false
    private var startGeneration: UInt64 = 0
    private var onMatch: ((String) -> Void)?
    private var onFailure: ((AgentOptionSpeechRecognitionFailure) -> Void)?

    public private(set) var isListening = false

    public override init() {
        super.init()
    }

    public func start(
        question: AgentInputQuestion,
        onMatch: @escaping (String) -> Void,
        onFailure: @escaping (AgentOptionSpeechRecognitionFailure) -> Void,
        preferredLanguageCode: String? = nil)
    {
        cancel()
        startGeneration &+= 1
        let generation = startGeneration
        self.onMatch = onMatch
        self.onFailure = onFailure

        let labels = question.options.map(\.label)
        guard AgentSpeechOptionMatcher.isValid(labels: labels) else {
            fail(.unavailable)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.authorizeMicrophoneAndSpeech() else {
                guard self.startGeneration == generation else { return }
                self.fail(.permissionDenied)
                return
            }
            guard !Task.isCancelled, self.startGeneration == generation else { return }
            self.beginRecognition(
                question: question,
                labels: labels,
                generation: generation,
                preferredLanguageCode: preferredLanguageCode)
        }
    }

    public func cancel() {
        startGeneration &+= 1
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if let audioEngine {
            if audioEngine.isRunning { audioEngine.stop() }
            if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0) }
        }
        tapInstalled = false
        audioEngine = nil
        recognizer = nil
        isListening = false
        onMatch = nil
        onFailure = nil
    }

    private func authorizeMicrophoneAndSpeech() async -> Bool {
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let microphoneGranted: Bool
        switch microphoneStatus {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            microphoneGranted = await Self.requestMicrophoneAccess()
        case .denied, .restricted:
            microphoneGranted = false
        @unknown default:
            microphoneGranted = false
        }
        guard microphoneGranted else { return false }

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        switch speechStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await Self.requestSpeechAuthorization()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private nonisolated static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func beginRecognition(
        question: AgentInputQuestion,
        labels: [String],
        generation: UInt64,
        preferredLanguageCode: String?)
    {
        let languageCode = AgentSpeechOptionMatcher.languageCode(
            question: question.question,
            header: question.header,
            labels: labels,
            preferredLanguageCode: preferredLanguageCode)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)),
              recognizer.isAvailable
        else {
            fail(.unavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.contextualStrings = AgentSpeechOptionMatcher.contextualStrings(for: labels)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            fail(.unavailable)
            return
        }
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: recordingFormat,
            block: Self.makeAudioTap(request: request))

        self.recognizer = recognizer
        self.recognitionRequest = request
        self.audioEngine = engine
        self.tapInstalled = true
        self.isListening = true

        self.recognitionTask = recognizer.recognitionTask(
            with: request,
            resultHandler: makeRecognitionHandler(labels: labels, generation: generation))

        engine.prepare()
        do {
            try engine.start()
        } catch {
            fail(.unavailable)
        }
    }

    private nonisolated static func makeAudioTap(
        request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock
    {
        { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated func makeRecognitionHandler(
        labels: [String],
        generation: UInt64) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
    {
        { [weak self] result, error in
            let hasError = error != nil
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.startGeneration == generation else { return }
                if hasError {
                    self.fail(.unavailable)
                } else {
                    self.handle(transcript: transcript, labels: labels, isFinal: isFinal)
                }
            }
        }
    }

    private func handle(transcript: String?, labels: [String], isFinal: Bool) {
        guard isListening else { return }
        if let transcript,
           let label = AgentSpeechOptionMatcher.match(transcript: transcript, labels: labels)
        {
            let callback = onMatch
            cancel()
            callback?(label)
            return
        }

        if isFinal { fail(.noMatch) }
    }

    private func fail(_ reason: AgentOptionSpeechRecognitionFailure) {
        let callback = onFailure
        cancel()
        callback?(reason)
    }
}
