import Foundation
import Logging

/// Voice mode state for UI rendering.
enum VoiceModeState: String, Sendable {
    case off
    case listening
    case speaking
    case processing
}

/// Central coordinator for Voice Mode.
/// Manages the lifecycle of speech recognition + synthesis, integrating
/// with ChatViewModel for auto-send and auto-read.
@MainActor
@Observable
final class VoiceModeService {
    static let shared = VoiceModeService()

    // MARK: - Observable State

    var isActive: Bool = false
    var state: VoiceModeState = .off
    var currentTranscript: String = ""
    var audioLevel: Float = 0

    /// Called when voice mode produces a final transcript to send.
    var onFinalTranscript: ((String) -> Void)?

    private let logger = Logger(label: "ai.mcclaw.voice-mode")
    private let recognition = SpeechRecognitionService.shared
    private let synthesis = SpeechSynthesisService.shared
    private var listenTask: Task<Void, Never>?

    // MARK: - Toggle

    /// Toggle voice mode on/off.
    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    /// Activate voice mode: start listening, set up auto-read.
    func activate() {
        guard !isActive else { return }
        isActive = true
        state = .listening
        logger.info("Voice mode activated")

        // Resume listening after TTS finishes
        synthesis.onFinishedSpeaking = { [weak self] in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.state = .listening
                self.startListening()
            }
        }

        startListening()
    }

    /// Deactivate voice mode: stop everything.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        state = .off
        currentTranscript = ""
        audioLevel = 0

        listenTask?.cancel()
        listenTask = nil
        recognition.stopListening()
        synthesis.stop()
        synthesis.onFinishedSpeaking = nil

        logger.info("Voice mode deactivated")
    }

    // MARK: - TTS Integration

    /// Speak an AI response (called by ChatViewModel when voice mode is active).
    func speakResponse(_ text: String) {
        guard isActive else { return }
        // Pause listening while speaking to avoid feedback loop
        recognition.stopListening()
        listenTask?.cancel()
        listenTask = nil
        state = .speaking
        synthesis.speak(text)
    }

    /// Feed streaming chunks for TTS.
    func speakResponseChunk(_ chunk: String) {
        guard isActive else { return }
        if state != .speaking {
            // First chunk — pause listening
            recognition.stopListening()
            listenTask?.cancel()
            listenTask = nil
            state = .speaking
        }
        synthesis.speakStreaming(chunk)
    }

    /// Interrupt TTS (e.g., user starts talking).
    func interruptSpeaking() {
        synthesis.stop()
        if isActive {
            state = .listening
            startListening()
        }
    }

    // MARK: - Private

    private func startListening() {
        listenTask?.cancel()
        let stream = recognition.startListening()
        listenTask = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case .partialTranscript(let text):
                    self.currentTranscript = text
                    self.state = .listening

                case .finalTranscript(let text):
                    self.currentTranscript = ""
                    self.state = .processing
                    self.onFinalTranscript?(text)

                case .audioLevel(let level):
                    self.audioLevel = level

                case .error(let message):
                    self.logger.warning("Speech recognition error: \(message)")
                }
            }
        }
    }

    private init() {}
}
