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
    var silenceThreshold: TimeInterval = 2.0

    /// Language locale for recognition (nil = system default).
    var locale: Locale?

    private let logger = Logger(label: "ai.mcclaw.speech-recognition")
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var streamContinuation: AsyncStream<SpeechEvent>.Continuation?

    /// Guards against concurrent restarts cascading into each other.
    private var isRestarting: Bool = false
    /// Consecutive restart attempts without receiving any transcript.
    private var consecutiveEmptyRestarts: Int = 0
    /// Max consecutive empty restarts before pausing recognition.
    private let maxEmptyRestarts: Int = 3

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
        isRestarting = false
        consecutiveEmptyRestarts = 0
        currentTranscript = ""
    }

    // MARK: - Private

    private func beginRecognition() async {
        // If user explicitly chose a locale in Settings, use it.
        // Otherwise use the user's preferred language from System Settings.
        // Note: Locale.current is affected by the app's bundle localizations
        // and may not match the system language. Locale.preferredLanguages
        // always returns the user's actual language preference.
        // SFSpeechRecognizer() without params uses Siri's language instead.
        let effectiveLocale: Locale
        if let userLocale = locale {
            effectiveLocale = userLocale
        } else if let preferred = Locale.preferredLanguages.first {
            effectiveLocale = Locale(identifier: preferred)
        } else {
            effectiveLocale = Locale.current
        }
        guard let recognizer = SFSpeechRecognizer(locale: effectiveLocale),
              recognizer.isAvailable else {
            streamContinuation?.yield(.error("Speech recognizer not available for \(effectiveLocale.identifier)"))
            streamContinuation?.finish()
            return
        }
        logger.info("SFSpeechRecognizer using locale: \(recognizer.locale.identifier) (source: \(locale != nil ? "user setting" : "preferredLanguages"), preferredLanguages[0]: \(Locale.preferredLanguages.first ?? "nil"), Locale.current: \(Locale.current.identifier))")

        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in
                    cont.resume(returning: status == .authorized)
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
        // Use server-side recognition to respect the locale even if
        // on-device model for this language isn't downloaded.
        request.requiresOnDeviceRecognition = false

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            streamContinuation?.yield(.error("No audio input available"))
            streamContinuation?.finish()
            return
        }

        // Audio tap fires on RealtimeMessenger background queue — must break
        // @MainActor inheritance with @Sendable + nonisolated(unsafe) for
        // non-Sendable framework types.
        nonisolated(unsafe) let tapRequest = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { @Sendable [weak self] buffer, _ in
            tapRequest.append(buffer)
            let channelData = buffer.floatChannelData
            let frames = Int(buffer.frameLength)
            var level: Float = 0
            if let channelData, frames > 0 {
                var sum: Float = 0
                for i in 0..<frames {
                    let sample = channelData[0][i]
                    sum += sample * sample
                }
                level = min(sqrt(sum / Float(frames)) * 10, 1.0)
            }
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
        // Recognition callback fires on arbitrary thread — extract Sendable
        // values before hopping to MainActor.
        recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            // Extract Sendable values on the callback thread
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorDesc = error?.localizedDescription
            let errorDomain = (error as? NSError)?.domain
            let errorCode = (error as? NSError)?.code

            Task { @MainActor [weak self] in
                guard let self else { return }

                if let transcript {
                    self.currentTranscript = transcript
                    self.streamContinuation?.yield(.partialTranscript(transcript))
                    // Got real speech — reset the empty-restart counter
                    self.consecutiveEmptyRestarts = 0

                    // Reset silence timer
                    self.resetSilenceTimer()

                    if isFinal {
                        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !final.isEmpty {
                            self.streamContinuation?.yield(.finalTranscript(final))
                        }
                        self.currentTranscript = ""
                        // Restart recognition for continuous mode
                        self.restartRecognition()
                    }
                }

                if let errorDesc {
                    // Ignore cancellation errors (user or system cancelled)
                    if errorDomain == "kAFAssistantErrorDomain" && errorCode == 216 {
                        return
                    }
                    // "No speech detected" (code 1110) — not a transient error,
                    // just means silence. Restart quietly without counting as failure.
                    if errorDomain == "kAFAssistantErrorDomain" && errorCode == 1110 {
                        self.logger.debug("No speech detected — restarting quietly")
                        if self.isListening {
                            self.restartRecognition()
                        }
                        return
                    }
                    self.logger.warning("Recognition error: \(errorDesc) (domain: \(errorDomain ?? "?"), code: \(errorCode ?? -1))")
                    // Try to restart on transient errors (with limit)
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
        // Prevent concurrent restart cascades
        guard !isRestarting else {
            logger.debug("Restart already in progress — skipping")
            return
        }
        isRestarting = true

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        cleanupAudio()

        guard isListening else {
            isRestarting = false
            return
        }

        consecutiveEmptyRestarts += 1

        if consecutiveEmptyRestarts > maxEmptyRestarts {
            logger.info("Too many empty restarts (\(consecutiveEmptyRestarts)) — waiting longer before retry")
        }

        // Progressive backoff: 500ms normally, 3s after too many empty restarts
        let delay = consecutiveEmptyRestarts > maxEmptyRestarts
            ? Duration.seconds(3)
            : Duration.milliseconds(500)

        Task {
            try? await Task.sleep(for: delay)
            self.isRestarting = false
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
