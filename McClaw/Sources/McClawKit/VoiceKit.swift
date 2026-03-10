import Foundation

/// Pure logic helpers for Voice Mode, extracted for testability.
public enum VoiceKit {

    // MARK: - Text Cleaning for TTS

    /// Remove markdown artifacts from text before speaking.
    public static func cleanForSpeech(_ text: String) -> String {
        var result = text
        // Remove code blocks
        result = result.replacingOccurrences(of: "```[\\s\\S]*?```", with: " code block omitted ", options: .regularExpression)
        // Remove inline code
        result = result.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
        // Remove markdown links, keep text
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // Remove markdown formatting (* _ ~)
        result = result.replacingOccurrences(of: "[*_~]{1,3}", with: "", options: .regularExpression)
        // Remove headers ((?m) enables multiline mode for ^ anchors)
        result = result.replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
        // Remove bullet points
        result = result.replacingOccurrences(of: "(?m)^[\\s]*[-*+]\\s+", with: "", options: .regularExpression)
        // Remove numbered lists prefix
        result = result.replacingOccurrences(of: "(?m)^[\\s]*\\d+\\.\\s+", with: "", options: .regularExpression)
        // Remove horizontal rules
        result = result.replacingOccurrences(of: "(?m)^[-*_]{3,}$", with: "", options: .regularExpression)
        // Collapse whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sentence Splitting

    /// Split text into sentences for natural TTS pacing.
    public static func splitIntoSentences(_ text: String) -> [String] {
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

    // MARK: - Wake Word Matching

    /// Check if any trigger word appears in the transcript.
    /// Returns the matched trigger word, or nil.
    public static func matchWakeWord(transcript: String, triggerWords: [String]) -> String? {
        let lower = transcript.lowercased()
        for trigger in triggerWords {
            let triggerLower = trigger.lowercased()
            if lower.contains(triggerLower) {
                return trigger
            }
        }
        return nil
    }

    // MARK: - Audio Level Normalization

    /// Normalize a raw RMS audio level to 0...1 range.
    /// Typical speech RMS is 0.01-0.1.
    public static func normalizeAudioLevel(_ rms: Float, gain: Float = 10.0) -> Float {
        min(max(rms * gain, 0), 1.0)
    }

    // MARK: - Voice Mode Config

    /// Voice mode configuration for persistence.
    public struct VoiceConfig: Codable, Sendable, Equatable {
        public var voiceModeEnabled: Bool
        public var selectedVoice: String?
        public var speechRate: Float
        public var speechVolume: Float
        public var silenceThreshold: TimeInterval
        public var recognitionLocale: String?
        public var wakeWordEnabled: Bool
        public var triggerWords: [String]
        public var pushToTalkEnabled: Bool
        public var pushToTalkKeyCode: UInt16

        public init(
            voiceModeEnabled: Bool = false,
            selectedVoice: String? = nil,
            speechRate: Float = 180,
            speechVolume: Float = 1.0,
            silenceThreshold: TimeInterval = 1.5,
            recognitionLocale: String? = nil,
            wakeWordEnabled: Bool = false,
            triggerWords: [String] = ["hey claw"],
            pushToTalkEnabled: Bool = false,
            pushToTalkKeyCode: UInt16 = 0x3D
        ) {
            self.voiceModeEnabled = voiceModeEnabled
            self.selectedVoice = selectedVoice
            self.speechRate = speechRate
            self.speechVolume = speechVolume
            self.silenceThreshold = silenceThreshold
            self.recognitionLocale = recognitionLocale
            self.wakeWordEnabled = wakeWordEnabled
            self.triggerWords = triggerWords
            self.pushToTalkEnabled = pushToTalkEnabled
            self.pushToTalkKeyCode = pushToTalkKeyCode
        }
    }

    // MARK: - Silence Detection

    /// Determine if enough silence has passed given timestamps.
    public static func shouldAutoSend(
        lastSpeechTime: Date,
        now: Date,
        threshold: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(lastSpeechTime) >= threshold
    }
}
