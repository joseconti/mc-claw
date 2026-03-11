import Foundation
import Speech
import AVFoundation
import AppKit
import Logging

/// Wake-word detection using SFSpeechRecognizer in low-power continuous mode.
/// Listens for configurable trigger phrases and activates Voice Mode when detected.
@MainActor
@Observable
final class VoiceWakeRuntime {
    static let shared = VoiceWakeRuntime()

    var isRunning: Bool = false
    var lastDetectedWord: String?

    /// Callback when wake word is detected.
    var onWakeWordDetected: (() -> Void)?

    private let logger = Logger(label: "ai.mcclaw.voice-wake")
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var triggerWords: [String] = []
    private var restartTask: Task<Void, Never>?

    // MARK: - Public API

    /// Start listening for wake words.
    func start(triggerWords: [String]) {
        guard !isRunning else { return }
        self.triggerWords = triggerWords.map { $0.lowercased() }
        isRunning = true
        logger.info("Voice wake started with triggers: \(triggerWords)")
        beginDetection()
    }

    /// Stop listening.
    func stop() {
        isRunning = false
        restartTask?.cancel()
        restartTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        cleanupAudio()
        logger.info("Voice wake stopped")
    }

    // MARK: - Private

    private func beginDetection() {
        guard isRunning else { return }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            logger.warning("Speech recognizer not available for wake word detection")
            scheduleRestart()
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Use on-device recognition if available for lower latency
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            logger.warning("No audio input for wake word detection")
            scheduleRestart()
            return
        }

        // Capture request as nonisolated(unsafe) to avoid actor-isolation check
        // on the real-time audio thread. This is safe because SFSpeechAudioBufferRecognitionRequest.append
        // is thread-safe and designed to be called from audio tap callbacks.
        nonisolated(unsafe) let tapRequest = request
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            tapRequest.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            logger.error("Audio engine failed for wake detection: \(error)")
            scheduleRestart()
            return
        }

        self.audioEngine = engine
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }

                if let result {
                    let text = result.bestTranscription.formattedString.lowercased()
                    // Check if any trigger word appears in the transcript
                    for trigger in self.triggerWords {
                        if text.contains(trigger) {
                            self.lastDetectedWord = trigger
                            self.logger.info("Wake word detected: \(trigger)")
                            // Play activation sound
                            NSSound.beep()
                            self.onWakeWordDetected?()
                            // Restart detection after a brief pause
                            self.restartDetection()
                            return
                        }
                    }
                }

                if let error {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        return // Cancelled, expected
                    }
                    self.logger.debug("Wake detection error: \(error.localizedDescription)")
                    self.restartDetection()
                }
            }
        }
    }

    private func restartDetection() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        cleanupAudio()
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard isRunning else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.isRunning else { return }
            self.beginDetection()
        }
    }

    private func cleanupAudio() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private init() {}
}
