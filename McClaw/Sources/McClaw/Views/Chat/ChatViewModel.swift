import SwiftUI
import Logging
import McClawKit

/// View model for the chat window. Manages messages and CLI interaction.
@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming: Bool = false

    private let logger = Logger(label: "ai.mcclaw.chat-vm")
    private let sessionStore = SessionStore.shared
    private let enrichmentService = PromptEnrichmentService.shared
    private var streamTask: Task<Void, Never>?
    /// Tracks the last provider used, to detect mid-conversation switches.
    private var lastUsedProviderId: String?
    /// True when session was restored from disk and first new message needs context injection.
    private var needsContextInjection = false
    /// Providers that have been used in this session (persisted or current).
    /// Used to determine --resume vs --session-id for Claude CLI.
    private var providersUsedInSession: Set<String> = []
    /// Whether the connectors header has been injected in this conversation turn.
    private var headerInjectedThisTurn = false

    /// Register this view model to receive chat messages from Gateway.
    func subscribeToGateway() {
        Task {
            await GatewayConnectionService.shared.setOnChatMessage { [weak self] text, sessionId in
                self?.handleGatewayMessage(text: text, sessionId: sessionId)
            }
        }
    }

    /// Handle an incoming chat message pushed by the Gateway.
    func handleGatewayMessage(text: String, sessionId: String) {
        let message = ChatMessage(
            role: .assistant,
            content: text,
            sessionId: sessionId
        )
        messages.append(message)
        logger.info("Received Gateway chat message for session \(sessionId)")

        // Speak gateway messages if voice mode is active
        if VoiceModeService.shared.isActive {
            VoiceModeService.shared.speakResponse(text)
        }
    }

    /// Send a message to the active CLI provider.
    func send(_ text: String, attachments: [Attachment] = []) async {
        // Intercept slash commands
        if text.hasPrefix("/") {
            if handleSlashCommand(text) { return }
        }

        let appState = AppState.shared
        guard let provider = appState.currentCLI else {
            logger.error("No CLI provider selected")
            let systemMessage = ChatMessage(
                role: .system,
                content: "No AI CLI detected. Please install one from Settings → CLIs, then restart the app.",
                sessionId: appState.currentSessionId ?? "main"
            )
            messages.append(systemMessage)
            return
        }

        let sessionId = appState.currentSessionId ?? "main"

        // Determine if we need to inject conversation context.
        // Context is needed when:
        // 1. Provider switched mid-conversation (e.g. Claude → Gemini)
        // 2. Session restored from disk and there are messages the current provider hasn't seen
        // For Claude CLI with --resume: only inject if there are messages from OTHER providers
        let providerSwitched = lastUsedProviderId != nil && lastUsedProviderId != provider.id
        var messageForCLI = text

        let hasMessagesFromOtherProviders = messages.contains {
            ($0.role == .user || $0.role == .assistant) && $0.providerId != nil && $0.providerId != provider.id
        }
        let needsManualContext = needsContextInjection || providerSwitched
        let shouldInjectContext: Bool
        if provider.id == "claude" {
            // Claude has --resume, but only for messages it processed.
            // If there are messages from other providers, inject those as context.
            shouldInjectContext = needsManualContext && hasMessagesFromOtherProviders
        } else {
            // Other providers always need context when resuming
            shouldInjectContext = needsManualContext && !messages.isEmpty
        }

        if shouldInjectContext {
            let context = buildContextHandoff(excluding: provider.id == "claude" ? "claude" : nil)
            if !context.isEmpty {
                messageForCLI = "\(context)\n\nUser's new message: \(text)"
                logger.info("Injecting context for \(provider.id) (resumed=\(needsContextInjection), switched=\(providerSwitched))")
            }
        }
        needsContextInjection = false
        lastUsedProviderId = provider.id

        // Prepend connectors header on the first message of a turn (if connectors active)
        if !headerInjectedThisTurn, let header = enrichmentService.buildConnectorsHeader() {
            messageForCLI = "\(header)\n\n\(messageForCLI)"
            headerInjectedThisTurn = true
        }

        // Add user message (show original text, not the context-enriched version)
        let userMessage = ChatMessage(
            role: .user,
            content: text,
            sessionId: sessionId,
            attachments: attachments,
            providerId: provider.id
        )
        messages.append(userMessage)

        // Stream the message and handle @fetch loops
        await streamAndEnrich(
            message: messageForCLI,
            originalText: text,
            attachments: attachments,
            provider: provider,
            sessionId: sessionId,
            fetchRound: 1
        )
    }

    /// Stream a message to the CLI and handle @fetch enrichment loops.
    private func streamAndEnrich(
        message: String,
        originalText: String,
        attachments: [Attachment],
        provider: CLIProviderInfo,
        sessionId: String,
        fetchRound: Int
    ) async {
        let appState = AppState.shared

        // Create assistant message placeholder (only on first round)
        var assistantMessage: ChatMessage
        if fetchRound == 1 {
            assistantMessage = ChatMessage(
                role: .assistant,
                content: "",
                sessionId: sessionId,
                isStreaming: true,
                providerId: provider.id
            )
            messages.append(assistantMessage)
        } else {
            // On subsequent rounds, reuse the last assistant message
            assistantMessage = messages.last ?? ChatMessage(
                role: .assistant, content: "", sessionId: sessionId, isStreaming: true, providerId: provider.id
            )
            assistantMessage.isStreaming = true
            assistantMessage.content = ""
            updateLastMessage(assistantMessage)
        }

        isStreaming = true
        appState.isWorking = true

        // Track accumulated text for TTS
        var accumulatedForTTS = ""
        let voiceActive = VoiceModeService.shared.isActive

        // Determine session continuity for CLI.
        let isResume = providersUsedInSession.contains(provider.id)
        providersUsedInSession.insert(provider.id)

        // Build project system prompt if this session belongs to a project
        let projectSystemPrompt = buildProjectSystemPrompt(sessionId: sessionId)

        // Build skills system prompt from local skills
        let skillsPrompt = SkillsKit.buildSkillsSystemPrompt(
            skills: LocalSkillsStore.shared.activeSkills()
        )

        // Combine prompts
        let combinedPrompt: String? = [projectSystemPrompt, skillsPrompt]
            .compactMap { $0 }
            .joined(separator: "\n\n")
            .isEmpty == true ? nil : [projectSystemPrompt, skillsPrompt]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        let stream = await CLIBridge.shared.send(
            message: message,
            provider: provider,
            sessionId: sessionId,
            isResume: isResume,
            systemPrompt: combinedPrompt
        )

        streamTask = Task {
            var hasError = false
            for await event in stream {
                switch event {
                case .text(let chunk):
                    assistantMessage.content += chunk
                    updateLastMessage(assistantMessage)

                    // Stream TTS: accumulate and speak at sentence boundaries
                    if voiceActive {
                        accumulatedForTTS += chunk
                        if accumulatedForTTS.hasSuffix(".") || accumulatedForTTS.hasSuffix("!") ||
                           accumulatedForTTS.hasSuffix("?") || accumulatedForTTS.hasSuffix("\n") {
                            VoiceModeService.shared.speakResponseChunk(accumulatedForTTS)
                            accumulatedForTTS = ""
                        }
                    }

                case .toolStart(let name, let id):
                    let toolCall = ToolCall(id: id, name: name, arguments: "", status: .running)
                    assistantMessage.toolCalls.append(toolCall)
                    updateLastMessage(assistantMessage)

                case .toolResult(let id, let result):
                    if let idx = assistantMessage.toolCalls.firstIndex(where: { $0.id == id }) {
                        assistantMessage.toolCalls[idx].result = result
                        assistantMessage.toolCalls[idx].status = .completed
                        updateLastMessage(assistantMessage)
                    }

                case .thinking(let thought):
                    logger.debug("Thinking: \(thought.prefix(100))")

                case .error(let error):
                    assistantMessage.content += "\n[Error: \(error)]"
                    updateLastMessage(assistantMessage)
                    hasError = true

                case .usage(let input, let output):
                    logger.info("Usage: \(input) in / \(output) out tokens")
                    UsageTracker.shared.record(
                        provider: provider.id,
                        inputTokens: input,
                        outputTokens: output,
                        pricing: provider.supportedModels.first?.pricing
                    )

                case .done:
                    assistantMessage.isStreaming = false
                    updateLastMessage(assistantMessage)

                    // Speak any remaining accumulated text
                    if voiceActive && !accumulatedForTTS.isEmpty {
                        VoiceModeService.shared.speakResponseChunk(accumulatedForTTS)
                        accumulatedForTTS = ""
                    }
                }
            }

            // Check for @fetch commands in the AI response
            if !hasError && ConnectorsKit.containsFetchCommand(assistantMessage.content) &&
               fetchRound < ConnectorsKit.maxFetchRoundsPerTurn {
                let (cleanResponse, fetchResults) = await self.enrichmentService.parseAndExecuteFetch(
                    response: assistantMessage.content,
                    round: fetchRound
                )

                if let fetchResults {
                    // Show clean response to user, then re-send with fetched data
                    assistantMessage.content = cleanResponse
                    assistantMessage.isStreaming = false
                    self.updateLastMessage(assistantMessage)

                    self.logger.info("@fetch round \(fetchRound): re-sending with fetched data")
                    await self.streamAndEnrich(
                        message: fetchResults,
                        originalText: originalText,
                        attachments: attachments,
                        provider: provider,
                        sessionId: sessionId,
                        fetchRound: fetchRound + 1
                    )
                    return
                }
            }

            isStreaming = false
            appState.isWorking = false

            // Reset header injection flag for next turn
            self.headerInjectedThisTurn = false

            // Model failover: if error and no content, try another provider
            if hasError && assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[Error") {
                if let fallback = self.findFallbackProvider(excluding: provider.id) {
                    assistantMessage.content += "\nFailing over to \(fallback.displayName)…"
                    self.updateLastMessage(assistantMessage)
                    appState.currentCLIIdentifier = fallback.id
                    self.logger.info("Failover: \(provider.id) → \(fallback.id)")
                    await self.send(originalText, attachments: attachments)
                    return
                }
            }

            // Auto-save session after streaming completes
            self.persistCurrentSession()
        }
    }

    /// Abort the current streaming response.
    func abort() async {
        streamTask?.cancel()
        streamTask = nil
        await CLIBridge.shared.abort()
        isStreaming = false
        AppState.shared.isWorking = false

        // Stop TTS if aborting
        if VoiceModeService.shared.isActive {
            SpeechSynthesisService.shared.stop()
        }

        if var last = messages.last, last.role == .assistant {
            last.isStreaming = false
            last.content += "\n[Aborted]"
            updateLastMessage(last)
        }
    }

    /// Update the last message in the array.
    private func updateLastMessage(_ message: ChatMessage) {
        if !messages.isEmpty {
            messages[messages.count - 1] = message
        }
    }

    // MARK: - Context Handoff

    /// Build a conversation summary to inject when switching providers or resuming.
    /// - Parameter excluding: If set, only include messages NOT from this provider
    ///   (used for Claude which has --resume for its own messages but needs context from others).
    private func buildContextHandoff(excluding providerId: String? = nil) -> String {
        var relevant = messages.filter { $0.role == .user || $0.role == .assistant }
        if let excludeId = providerId {
            // Only include messages from OTHER providers (ones the current provider hasn't seen)
            relevant = relevant.filter { $0.providerId != excludeId }
        }
        guard !relevant.isEmpty else { return "" }

        // Take last 10 messages max, truncate long ones
        let recent = relevant.suffix(10)
        var lines: [String] = ["[Previous conversation context]"]
        for msg in recent {
            let role = msg.role == .user ? "User" : "Assistant"
            let via = msg.providerId.map { " (via \($0))" } ?? ""
            let content = msg.content.prefix(500)
            let truncated = msg.content.count > 500 ? "..." : ""
            lines.append("\(role)\(via): \(content)\(truncated)")
        }
        lines.append("[End of context — continue the conversation naturally]")
        return lines.joined(separator: "\n")
    }

    // MARK: - Project Context

    /// Build a system prompt from the project's rules and cross-chat context digest.
    /// Returns nil if the session doesn't belong to a project or the project has no rules/context.
    private func buildProjectSystemPrompt(sessionId: String) -> String? {
        let sessionStore = SessionStore.shared
        let projectStore = ProjectStore.shared

        // Find which project this session belongs to.
        // Check sessionStore first, then scan all projects (for brand-new sessions not yet persisted).
        var projectId: String?
        if let sessionInfo = sessionStore.sessions.first(where: { $0.id == sessionId }) {
            projectId = sessionInfo.projectId
        }
        if projectId == nil {
            // New session not yet in sessionStore — check projects directly
            projectId = projectStore.projects.first(where: { $0.sessionIds.contains(sessionId) })?.id
        }
        guard let projectId, let project = projectStore.load(projectId: projectId) else {
            return nil
        }

        var parts: [String] = []

        // 0. Project identity — always present so the AI knows the project context
        parts.append("# Project: \(project.name)")
        if !project.description.isEmpty {
            parts.append("Description: \(project.description)")
        }
        parts.append("")
        parts.append("IMPORTANT: This conversation belongs to the project described above. Focus all your answers on this project's topic and goals. Do NOT explore or reference the local filesystem — the working directory is unrelated to this project. Use only the project context provided here (rules, files, previous conversations).")

        // 1. Project rules
        if !project.rules.isEmpty {
            parts.append("")
            parts.append("# Project Rules")
            parts.append(project.rules)
        }

        // 2. Project files context
        if let filesContext = ProjectFileStore.shared.buildFilesContext(for: projectId) {
            parts.append("")
            parts.append("# Project Files")
            parts.append("The following files have been uploaded to this project. Use them as reference.")
            parts.append("")
            parts.append(filesContext)
        }

        // 3. Cross-chat context digest (summaries from sibling chats)
        let siblingSessionIds = project.sessionIds.filter { $0 != sessionId }
        if !siblingSessionIds.isEmpty {
            let digest = buildCrossChatDigest(siblingSessionIds: siblingSessionIds)
            if !digest.isEmpty {
                parts.append("")
                parts.append("# Related Conversations in This Project")
                parts.append("The following is a summary of other conversations in the same project. Use this context to maintain coherence across chats.")
                parts.append("")
                parts.append(digest)
            }
        }

        let result = parts.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    /// Build a digest of key messages from sibling chats in the same project.
    /// Takes the first user message (topic) and last exchange from each chat.
    private func buildCrossChatDigest(siblingSessionIds: [String]) -> String {
        let sessionStore = SessionStore.shared
        var lines: [String] = []

        // Limit to 8 most recent sibling chats to avoid token explosion
        let recentSiblings = Array(siblingSessionIds.prefix(8))

        for siblingId in recentSiblings {
            guard let messages = sessionStore.load(sessionId: siblingId) else { continue }
            let meaningful = messages.filter { $0.role == .user || $0.role == .assistant }
            guard !meaningful.isEmpty else { continue }

            // Get the chat title (first user message)
            let title = meaningful.first(where: { $0.role == .user })?.content.prefix(100) ?? "Untitled"
            lines.append("## Chat: \(title)")

            // Include first user message as topic
            if let firstUser = meaningful.first(where: { $0.role == .user }) {
                let content = String(firstUser.content.prefix(300))
                lines.append("Topic: \(content)")
            }

            // Include last exchange (last user + last assistant)
            let lastMessages = meaningful.suffix(4)
            for msg in lastMessages {
                let role = msg.role == .user ? "User" : "Assistant"
                let content = String(msg.content.prefix(200))
                let truncated = msg.content.count > 200 ? "…" : ""
                lines.append("\(role): \(content)\(truncated)")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Model Failover

    /// Find an alternative CLI provider when the current one fails.
    private func findFallbackProvider(excluding providerId: String) -> CLIProviderInfo? {
        AppState.shared.availableCLIs.first {
            $0.id != providerId && $0.isInstalled && $0.isAuthenticated
        }
    }

    // MARK: - Slash Commands

    /// Process a slash command. Returns true if the command was handled.
    private func handleSlashCommand(_ input: String) -> Bool {
        let parts = input.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0].lowercased()
        let argument = parts.count > 1 ? parts[1] : nil
        let appState = AppState.shared
        let sessionId = appState.currentSessionId ?? "main"

        switch command {
        case "/status":
            let cliName = appState.currentCLI?.displayName ?? "None"
            let cliVersion = appState.currentCLI?.version ?? "?"
            let gateway = appState.gatewayStatus.rawValue.capitalized
            let session = sessionId
            let msgCount = messages.count
            let voice = VoiceModeService.shared.isActive ? "Active" : "Off"
            let version = UpdaterService.shared.currentVersion

            postSystem("""
            **McClaw Status**
            - Version: \(version)
            - CLI: \(cliName) v\(cliVersion)
            - Gateway: \(gateway)
            - Session: `\(session)` (\(msgCount) messages)
            - Voice: \(voice)
            - Channels: \(appState.activeChannels.count) active
            - Plugins: \(appState.loadedPlugins.count) loaded
            """, sessionId: sessionId)
            return true

        case "/new":
            // Save current session before switching
            persistCurrentSession()
            let newId = UUID().uuidString
            appState.currentSessionId = newId
            messages.removeAll()
            providersUsedInSession.removeAll()
            postSystem("New session started: `\(newId)`", sessionId: newId)
            logger.info("New chat session: \(newId)")
            return true

        case "/reset":
            messages.removeAll()
            providersUsedInSession.removeAll()
            postSystem("Chat history cleared.", sessionId: sessionId)
            return true

        case "/compact":
            let totalBefore = messages.count
            // Keep system messages and last 10 messages
            let systemMessages = messages.filter { $0.role == .system }
            let recentMessages = messages.suffix(10)
            var compacted = systemMessages
            for msg in recentMessages where !compacted.contains(where: { $0.id == msg.id }) {
                compacted.append(msg)
            }
            messages = compacted
            let removed = totalBefore - messages.count
            postSystem("Compacted: removed \(removed) older messages, kept \(messages.count).", sessionId: sessionId)
            return true

        case "/think":
            guard let prompt = argument, !prompt.isEmpty else {
                postSystem("Usage: `/think <prompt>` — Sends with extended thinking enabled.", sessionId: sessionId)
                return true
            }
            // Prefix with thinking instruction for the CLI
            Task { await send("[Think step by step] \(prompt)") }
            return true

        case "/model":
            if let modelName = argument, !modelName.isEmpty {
                // Try to find a CLI matching the model name
                if let match = appState.availableCLIs.first(where: {
                    $0.displayName.localizedCaseInsensitiveContains(modelName) ||
                    $0.id.localizedCaseInsensitiveContains(modelName)
                }) {
                    appState.currentCLIIdentifier = match.id
                    Task { await ConfigStore.shared.saveFromState() }
                    postSystem("Switched to **\(match.displayName)**.", sessionId: sessionId)
                } else {
                    let available = appState.availableCLIs.map(\.displayName).joined(separator: ", ")
                    postSystem("Unknown model `\(modelName)`. Available: \(available)", sessionId: sessionId)
                }
            } else {
                let current = appState.currentCLI?.displayName ?? "None"
                let available = appState.availableCLIs.map { cli in
                    cli.id == appState.currentCLIIdentifier ? "**\(cli.displayName)** (active)" : cli.displayName
                }.joined(separator: ", ")
                postSystem("Current: **\(current)**\nAvailable: \(available)", sessionId: sessionId)
            }
            return true

        case "/provider":
            // Alias for /model
            return handleSlashCommand("/model\(argument.map { " \($0)" } ?? "")")

        case "/session":
            if let name = argument, !name.isEmpty {
                // Save current session before switching
                persistCurrentSession()
                appState.currentSessionId = name
                // Try to load existing session
                if let loaded = sessionStore.load(sessionId: name) {
                    messages = loaded
                    // Rebuild providers used set from loaded messages
                    providersUsedInSession.removeAll()
                    for msg in loaded where msg.role == .user || msg.role == .assistant {
                        if let pid = msg.providerId { providersUsedInSession.insert(pid) }
                    }
                    needsContextInjection = loaded.contains { $0.role == .user || $0.role == .assistant }
                    postSystem("Resumed session: `\(name)` (\(loaded.count) messages)", sessionId: name)
                } else {
                    messages.removeAll()
                    providersUsedInSession.removeAll()
                    postSystem("New session: `\(name)`", sessionId: name)
                }
            } else {
                let savedCount = sessionStore.sessions.count
                var response = "Current session: `\(sessionId)`\n"
                if savedCount > 0 {
                    let recent = sessionStore.sessions.prefix(5)
                    response += "Recent sessions:\n"
                    for s in recent {
                        response += "- `\(s.id)` — \(s.title) (\(s.messageCount) msgs)\n"
                    }
                }
                response += "\nUsage: `/session <name>` — Switch to a named session."
                postSystem(response, sessionId: sessionId)
            }
            return true

        case "/fetch":
            guard let fetchArg = argument, !fetchArg.isEmpty else {
                postSystem("Usage: `/fetch connector.action param=value` — Fetch data from a connected service.", sessionId: sessionId)
                return true
            }
            Task {
                let result = await enrichmentService.executeSlashFetch(input)
                postSystem(result, sessionId: sessionId)
            }
            return true

        case "/help":
            postSystem("""
            **Available Commands**
            - `/status` — Show app status (CLI, Gateway, session, version)
            - `/new` — Start a new chat session
            - `/reset` — Clear chat history (keeps session)
            - `/compact` — Remove older messages, keep last 10
            - `/think <prompt>` — Send with extended thinking
            - `/model [name]` — Show or switch CLI provider
            - `/provider [name]` — Alias for /model
            - `/session [name]` — Show or switch session
            - `/fetch connector.action` — Fetch data from a connector
            - `/help` — Show this help
            """, sessionId: sessionId)
            return true

        default:
            // Not a recognized command — pass through to CLI
            return false
        }
    }

    /// Post a system message to the chat.
    private func postSystem(_ content: String, sessionId: String) {
        messages.append(ChatMessage(role: .system, content: content, sessionId: sessionId))
    }

    // MARK: - Session Persistence

    /// Save current messages to disk.
    func persistCurrentSession() {
        let appState = AppState.shared
        guard let sessionId = appState.currentSessionId, !messages.isEmpty else { return }
        // Only persist user/assistant messages (skip empty or system-only sessions)
        let meaningful = messages.filter { $0.role == .user || $0.role == .assistant }
        guard !meaningful.isEmpty else { return }
        sessionStore.save(sessionId: sessionId, messages: messages, provider: appState.currentCLI?.id)
    }

    /// Load the current session from disk (called on app launch).
    func loadCurrentSession() {
        let appState = AppState.shared
        sessionStore.refreshIndex()
        guard let sessionId = appState.currentSessionId,
              let loaded = sessionStore.load(sessionId: sessionId) else { return }
        messages = loaded
        lastUsedProviderId = appState.currentCLIIdentifier

        // Collect all providers that have been used in this session.
        // This ensures --resume is used for providers that already have a CLI session.
        let meaningful = loaded.filter { $0.role == .user || $0.role == .assistant }
        for msg in meaningful {
            if let pid = msg.providerId {
                providersUsedInSession.insert(pid)
            }
        }
        // If there are meaningful messages but none have providerId (old sessions),
        // assume the current provider was used.
        if !meaningful.isEmpty, providersUsedInSession.isEmpty,
           let currentCLI = appState.currentCLIIdentifier {
            providersUsedInSession.insert(currentCLI)
        }

        let hasMeaningful = !meaningful.isEmpty
        needsContextInjection = hasMeaningful
        logger.info("Restored session \(sessionId) with \(loaded.count) messages, providers=\(providersUsedInSession), needsContext=\(hasMeaningful)")
    }
}
