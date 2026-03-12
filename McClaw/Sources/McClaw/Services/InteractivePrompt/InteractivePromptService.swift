import Foundation
import Logging
import McClawKit

/// Manages the interactive prompt flow: presenting AI-generated prompts to the user,
/// collecting responses, and resuming the conversation.
/// Follows the same @MainActor @Observable singleton pattern as AgentInstallService.
@MainActor
@Observable
final class InteractivePromptService {
    static let shared = InteractivePromptService()

    var phase: InteractivePromptPhase = .idle
    var currentPrompts: [InteractivePromptKit.InteractivePrompt] = []
    var currentIndex: Int = 0
    var responses: [InteractivePromptKit.PromptResponse] = []

    private var promptContinuation: CheckedContinuation<[InteractivePromptKit.PromptResponse], Never>?
    private let logger = Logger(label: "ai.mcclaw.interactive-prompt")

    private init() {}

    // MARK: - Present Prompts

    /// Called by ChatViewModel after detecting prompts in AI response.
    /// Suspends until the user responds to all prompts (or skips).
    func presentPrompts(_ prompts: [InteractivePromptKit.InteractivePrompt]) async -> [InteractivePromptKit.PromptResponse] {
        currentPrompts = prompts
        currentIndex = 0
        responses = []
        phase = .presenting

        logger.info("Presenting \(prompts.count) interactive prompt(s)")

        return await withCheckedContinuation { continuation in
            self.promptContinuation = continuation
        }
    }

    // MARK: - Resolve

    /// Called by InteractivePromptCard when the user makes a selection.
    func resolveCurrentPrompt(_ response: InteractivePromptKit.PromptResponse) {
        responses.append(response)
        logger.info("Prompt \(response.promptId) resolved (skipped: \(response.skipped))")

        if currentIndex + 1 < currentPrompts.count {
            currentIndex += 1
        } else {
            completeAll()
        }
    }

    /// Skip all remaining prompts.
    func skipAll() {
        for i in currentIndex..<currentPrompts.count {
            responses.append(InteractivePromptKit.PromptResponse(
                promptId: currentPrompts[i].id,
                skipped: true
            ))
        }
        logger.info("All remaining prompts skipped")
        completeAll()
    }

    /// Skip just the current prompt and advance.
    func skipCurrent() {
        let response = InteractivePromptKit.PromptResponse(
            promptId: currentPrompts[currentIndex].id,
            skipped: true
        )
        resolveCurrentPrompt(response)
    }

    // MARK: - Reset

    func reset() {
        phase = .idle
        currentPrompts = []
        currentIndex = 0
        responses = []
        promptContinuation = nil
    }

    // MARK: - Private

    private func completeAll() {
        phase = .completed
        let continuation = promptContinuation
        promptContinuation = nil
        continuation?.resume(returning: responses)
    }
}

/// Phase of the interactive prompt flow.
enum InteractivePromptPhase: Sendable {
    case idle
    case presenting
    case completed
}
