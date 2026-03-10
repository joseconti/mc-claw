import Foundation
import Speech
import AVFoundation
import Logging

/// Events emitted by the speech recognition pipeline.
enum SpeechEvent: Sendable {
    case partialTranscript(String)
    case finalTranscript(String)
    case audioLevel(Float)
    case error(String)
}

/// Captures audio via AVAudioEngine and transcribes using SFSpeechRecognizer.
/// Emits SpeechEvents via AsyncStream. Detects silence to auto-finalize.
@MainActor
@Observable
final class SpeechRecognitionService {
    static let shared = SpeechRecognitionService()

    var isListening: Bool = false
    var currentTranscript: String = ""

    /// Silence threshold in seconds before auto-finalizing.
    var silenceThreshold: TimeInterval = 1.5

    /// Language locale for recognition (nil = system default).
    var locale: Locale?

    private let logger = Logger(label: "ai.mcclaw.speech-recognition")
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var streamContinuation: AsyncStream<SpeechEvent>.Continuation?

    // MARK: - Public API

    /// Start listening and return a stream of speech events.
    func startListening() -> AsyncStream<SpeechEvent> {
        // Stop any existing session
        stopListening()

        let stream = AsyncStream<SpeechEvent> { continuation in
            self.streamContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.cleanupAudio()
                }
            }
        }

        Task {
            await beginRecognition()
        }

        return stream
    }

    /// Stop listening and finalize.
    func stopListening() {
        silenceTimer?.cancel()
        silenceTimer = nil

        if let request = recognitionRequest {
            request.endAudio()
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        cleanupAudio()

        // Emit final transcript if we have one
        let transcript = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            streamContinuation?.yield(.finalTranscript(transcript))
        }

        streamContinuation?.finish()
        streamContinuation = nil

        isListening = false
        currentTranscript = ""
    }

    // MARK: - Private

    private func beginRecognition() async {
        let effectiveLocale = locale ?? Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: effectiveLocale),
              recognizer.isAvailable else {
            streamContinuation?.yield(.error("Speech recognizer not available for \(effectiveLocale.identifier)"))
            streamContinuation?.finish()
            return
        }

        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    // Callback fires on arbitrary thread — must not resume directly
                    // on @MainActor. Use Task to hop back safely.
                    Task { @MainActor in
                        cont.resume(returning: status == .authorized)
                    }
                }
            }
            guard granted else {
                streamContinuation?.yield(.error("Speech recognition permission denied"))
                streamContinuation?.finish()
                return
            }
        } else if authStatus != .authorized {
            streamContinuation?.yield(.error("Speech recognition not authorized"))
            streamContinuation?.finish()
            return
        }

        // Check microphone permission
        let micGranted = await PermissionManager.shared.requestMicrophone()
        guard micGranted else {
            streamContinuation?.yield(.error("Microphone permission denied"))
            streamContinuation?.finish()
            return
        }

        // Set up audio engine
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            streamContinuation?.yield(.error("No audio input available"))
            streamContinuation?.finish()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            // Calculate audio level
            let level = Self.calculateAudioLevel(buffer: buffer)
            Task { @MainActor [weak self] in
                self?.streamContinuation?.yield(.audioLevel(level))
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            streamContinuation?.yield(.error("Audio engine failed: \(error.localizedDescription)"))
            streamContinuation?.finish()
            return
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.isListening = true

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let transcript = result.bestTranscription.formattedString
                    self.currentTranscript = transcript
                    self.streamContinuation?.yield(.partialTranscript(transcript))

                    // Reset silence timer
                    self.resetSilenceTimer()

                    if result.isFinal {
                        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !final.isEmpty {
                            self.streamContinuation?.yield(.finalTranscript(final))
                        }
                        self.currentTranscript = ""
                        // Restart recognition for continuous mode
                        self.restartRecognition()
                    }
                }

                if let error {
                    let nsError = error as NSError
                    // Ignore cancellation errors
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // "Request was canceled" — expected during stop
                        return
                    }
                    self.logger.warning("Recognition error: \(error.localizedDescription)")
                    // Try to restart on transient errors
                    if self.isListening {
                        self.restartRecognition()
                    }
                }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.silenceThreshold))
            guard !Task.isCancelled else { return }

            let transcript = self.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                self.streamContinuation?.yield(.finalTranscript(transcript))
                self.currentTranscript = ""
                self.restartRecognition()
            }
        }
    }

    private func restartRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        cleanupAudio()

        guard isListening else { return }

        Task {
            // Brief pause before restarting
            try? await Task.sleep(for: .milliseconds(200))
            guard self.isListening else { return }
            await self.beginRecognition()
        }
    }

    private func cleanupAudio() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private static func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frames {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))
        // Normalize to 0...1 range (typical speech is ~0.01-0.1 RMS)
        return min(rms * 10, 1.0)
    }

    private init() {}
}
