import Foundation
import AppKit
import Logging

/// Text-to-Speech service using NSSpeechSynthesizer.
/// Reads AI responses aloud with configurable voice, rate, and volume.
@MainActor
@Observable
final class SpeechSynthesisService: NSObject {
    static let shared = SpeechSynthesisService()

    var isSpeaking: Bool = false
    var selectedVoice: String?
    var rate: Float = 180  // words per minute (default NSSpeechSynthesizer rate)
    var volume: Float = 1.0

    /// Callback when speech finishes (used to resume listening).
    var onFinishedSpeaking: (() -> Void)?

    private let logger = Logger(label: "ai.mcclaw.speech-synthesis")
    private var synthesizer: NSSpeechSynthesizer?
    private var utteranceQueue: [String] = []
    private var isProcessingQueue: Bool = false

    // MARK: - Public API

    /// Speak the given text. If already speaking, queues the text.
    func speak(_ text: String) {
        let cleaned = cleanForSpeech(text)
        guard !cleaned.isEmpty else { return }

        utteranceQueue.append(cleaned)
        processQueue()
    }

    /// Speak text that is still streaming — starts speaking the first chunk,
    /// appends subsequent chunks to the queue.
    func speakStreaming(_ chunk: String) {
        let cleaned = cleanForSpeech(chunk)
        guard !cleaned.isEmpty else { return }

        // Split on sentence boundaries for natural pacing
        let sentences = splitIntoSentences(cleaned)
        for sentence in sentences {
            utteranceQueue.append(sentence)
        }
        processQueue()
    }

    /// Stop speaking immediately and clear the queue.
    func stop() {
        utteranceQueue.removeAll()
        synthesizer?.stopSpeaking()
        isSpeaking = false
        isProcessingQueue = false
    }

    /// List available system voices.
    func availableVoices() -> [(identifier: String, name: String, locale: String)] {
        NSSpeechSynthesizer.availableVoices.compactMap { voiceId in
            guard let attrs = NSSpeechSynthesizer.attributes(forVoice: voiceId) as? [String: Any],
                  let name = attrs[NSSpeechSynthesizer.VoiceAttributeKey.name.rawValue] as? String else {
                return nil
            }
            let locale = (attrs[NSSpeechSynthesizer.VoiceAttributeKey.localeIdentifier.rawValue] as? String) ?? "unknown"
            return (identifier: voiceId.rawValue, name: name, locale: locale)
        }
    }

    /// Preview a voice by speaking a short sample.
    func previewVoice(_ voiceIdentifier: String) {
        stop()
        let synth = NSSpeechSynthesizer(voice: NSSpeechSynthesizer.VoiceName(rawValue: voiceIdentifier))
        synth?.rate = rate
        synth?.volume = volume
        synth?.startSpeaking("Hello, I am your AI assistant.")
        // Don't set isSpeaking for previews
    }

    // MARK: - Private

    private func processQueue() {
        guard !isProcessingQueue, !utteranceQueue.isEmpty else { return }
        isProcessingQueue = true
        isSpeaking = true

        let text = utteranceQueue.removeFirst()
        let synth = getOrCreateSynthesizer()
        synth.startSpeaking(text)
    }

    private func getOrCreateSynthesizer() -> NSSpeechSynthesizer {
        if let existing = synthesizer { return existing }

        let voiceName: NSSpeechSynthesizer.VoiceName?
        if let voice = selectedVoice {
            voiceName = NSSpeechSynthesizer.VoiceName(rawValue: voice)
        } else {
            voiceName = nil
        }

        let synth = NSSpeechSynthesizer(voice: voiceName) ?? NSSpeechSynthesizer()
        synth.delegate = self
        synth.rate = rate
        synth.volume = volume
        synthesizer = synth
        return synth
    }

    /// Remove markdown and code artifacts that don't sound good when spoken.
    private func cleanForSpeech(_ text: String) -> String {
        var result = text
        // Remove code blocks
        result = result.replacingOccurrences(of: "```[\\s\\S]*?```", with: "code block omitted", options: .regularExpression)
        // Remove inline code
        result = result.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
        // Remove markdown links, keep text
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // Remove markdown formatting
        result = result.replacingOccurrences(of: "[*_~]{1,3}", with: "", options: .regularExpression)
        // Remove headers
        result = result.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        // Collapse whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split text into sentences for more natural pacing.
    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        if sentences.isEmpty && !text.isEmpty {
            sentences = [text]
        }
        return sentences
    }

    private override init() {
        super.init()
    }
}

// MARK: - NSSpeechSynthesizerDelegate

extension SpeechSynthesisService: NSSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        Task { @MainActor in
            self.isProcessingQueue = false
            if !self.utteranceQueue.isEmpty {
                self.processQueue()
            } else {
                self.isSpeaking = false
                self.onFinishedSpeaking?()
            }
        }
    }
}
