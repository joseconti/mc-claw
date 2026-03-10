import Foundation
import AppKit
import Carbon.HIToolbox
import Logging

/// Push-to-talk service using global hotkey monitoring.
/// Hold the hotkey to record, release to send the transcript.
@MainActor
@Observable
final class PushToTalkService {
    static let shared = PushToTalkService()

    var isHolding: Bool = false
    var isEnabled: Bool = false

    /// The key code for push-to-talk (default: Right Option = kVK_RightOption = 0x3D).
    var hotKeyCode: UInt16 = 0x3D

    /// Called when push-to-talk produces a final transcript.
    var onTranscript: ((String) -> Void)?

    private let logger = Logger(label: "ai.mcclaw.push-to-talk")
    private let recognition = SpeechRecognitionService.shared
    private var eventMonitor: Any?
    private var listenTask: Task<Void, Never>?
    private var accumulatedTranscript: String = ""

    // MARK: - Public API

    /// Start monitoring for the push-to-talk hotkey.
    func start() {
        guard eventMonitor == nil else { return }
        isEnabled = true

        // Monitor key down/up globally (requires Accessibility permission)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }

        logger.info("Push-to-talk started (keyCode: \(hotKeyCode))")
    }

    /// Stop monitoring.
    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if isHolding {
            releaseKey()
        }
        isEnabled = false
        logger.info("Push-to-talk stopped")
    }

    // MARK: - Private

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        guard keyCode == hotKeyCode else { return }

        // Check if the key is currently pressed
        let isPressed: Bool
        switch hotKeyCode {
        case 0x3D: // Right Option
            isPressed = event.modifierFlags.contains(.option)
        case 0x3A: // Left Option
            isPressed = event.modifierFlags.contains(.option)
        case 0x3C: // Right Shift
            isPressed = event.modifierFlags.contains(.shift)
        case 0x38: // Left Shift
            isPressed = event.modifierFlags.contains(.shift)
        case 0x3E: // Right Control
            isPressed = event.modifierFlags.contains(.control)
        default:
            isPressed = false
        }

        if isPressed && !isHolding {
            pressKey()
        } else if !isPressed && isHolding {
            releaseKey()
        }
    }

    private func pressKey() {
        isHolding = true
        accumulatedTranscript = ""

        // Interrupt any ongoing TTS
        SpeechSynthesisService.shared.stop()

        // Start recognition
        let stream = recognition.startListening()
        listenTask = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case .partialTranscript(let text):
                    self.accumulatedTranscript = text
                case .finalTranscript(let text):
                    self.accumulatedTranscript = text
                case .audioLevel, .error:
                    break
                }
            }
        }

        logger.debug("Push-to-talk: key down")
    }

    private func releaseKey() {
        isHolding = false

        // Stop recognition
        recognition.stopListening()
        listenTask?.cancel()
        listenTask = nil

        // Send accumulated transcript
        let transcript = accumulatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            onTranscript?(transcript)
            logger.debug("Push-to-talk: sent transcript (\(transcript.count) chars)")
        }
        accumulatedTranscript = ""

        logger.debug("Push-to-talk: key up")
    }

    private init() {}
}
