import SwiftUI
import AppKit
import Logging
import McClawKit
import UniformTypeIdentifiers

/// View model for the chat window. Manages messages and CLI interaction.
@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isStreaming: Bool = false
    /// Set when a plan file is detected in a non-project chat, triggers ArtifactSaveSheet.
    var pendingArtifactSave: PendingArtifactSave?
    /// Active Git context for prompt enrichment (set by Git panel).
    var gitContext: GitContext?
    /// When set, overrides `AppState.currentSessionId` for session ID resolution (used by Git panel).
    var overrideSessionId: String?

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
    /// Tracks chain depth for multi-step Git confirmations. Max 10 to prevent loops.
    private var chainDepth: Int = 0
    /// Maximum allowed chain depth before stopping multi-step operations.
    private static let maxChainDepth = 10

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

    /// Send a pre-filled prompt to the chat (e.g., from contextual actions).
    /// If `autoSend` is true, the prompt is sent immediately. Otherwise it would need
    /// UI support for pre-filling the input bar (handled by the caller).
    func sendPrefilled(_ prompt: String) {
        Task { await send(prompt) }
    }

    /// Send a message to the active CLI provider.
    func send(_ text: String, attachments: [Attachment] = []) async {
        // Reset chain depth on new user message
        chainDepth = 0

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
                sessionId: overrideSessionId ?? appState.currentSessionId ?? "main"
            )
            messages.append(systemMessage)
            return
        }

        let sessionId = overrideSessionId ?? appState.currentSessionId ?? "main"

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

        // Prepend Git context header if a repo is selected
        if let ctx = gitContext {
            let gitHeader = enrichmentService.buildGitContextHeader(ctx)
            messageForCLI = "\(gitHeader)\n\n\(messageForCLI)"
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

    /// Find the first installed image-capable CLI provider.
    func imageCapableProvider() -> CLIProviderInfo? {
        AppState.shared.availableCLIs.first {
            $0.isInstalled && $0.isAuthenticated && $0.capabilities.supportsImageGeneration
        }
    }

    /// Send an image generation request. Uses Vertex AI Imagen 3 directly
    /// (same approach as project cover images) instead of routing through a CLI.
    func sendImageGeneration(prompt: String) async {
        let appState = AppState.shared
        let sessionId = overrideSessionId ?? appState.currentSessionId ?? "main"

        // Check that Gemini CLI is installed (needed for OAuth token)
        guard imageCapableProvider() != nil else {
            postSystem("No image-capable CLI detected. Install Gemini CLI to generate images.", sessionId: sessionId)
            return
        }

        // Show user message
        let userMessage = ChatMessage(
            role: .user,
            content: "🎨 \(prompt)",
            sessionId: sessionId,
            providerId: "gemini"
        )
        messages.append(userMessage)

        // Create assistant placeholder with shimmer
        var assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            sessionId: sessionId,
            isStreaming: true,
            isGeneratingImage: true,
            providerId: "gemini"
        )
        messages.append(assistantMessage)

        isStreaming = true
        appState.isWorking = true

        // Call Vertex AI Imagen 3 directly (not through CLI)
        let filePath = await ImageGenerationService.shared.generate(
            prompt: prompt,
            aspectRatio: "1:1"
        )

        if let filePath {
            let generated = GeneratedImage(
                filePath: filePath,
                prompt: prompt,
                providerUsed: "Imagen 3"
            )
            assistantMessage.generatedImages.append(generated)
            assistantMessage.content = ""
        } else {
            assistantMessage.content = String(localized: "Image generation failed. Make sure Gemini CLI is authenticated and Vertex AI API is enabled in your GCP project.", bundle: .module)
        }

        assistantMessage.isStreaming = false
        assistantMessage.isGeneratingImage = false
        updateLastMessage(assistantMessage)

        isStreaming = false
        appState.isWorking = false
        persistCurrentSession()

        // Refresh the image index so Multimedia gallery stays in sync
        ImageIndexStore.shared.refreshIndex()
    }

    // MARK: - Agent Install

    /// Send an install prompt to be parsed by the AI and presented as a plan.
    func sendInstallPrompt(_ prompt: String) async {
        let appState = AppState.shared
        let sessionId = overrideSessionId ?? appState.currentSessionId ?? "main"

        // Show user message
        let userMessage = ChatMessage(
            role: .user,
            content: "📦 " + String(localized: "Install:", bundle: .module) + " " + String(prompt.prefix(200)),
            sessionId: sessionId,
            providerId: appState.currentCLI?.id
        )
        messages.append(userMessage)

        // Show parsing indicator
        postSystem(String(localized: "Analyzing install prompt...", bundle: .module), sessionId: sessionId)

        // Parse via AI
        let service = AgentInstallService.shared
        await service.parseInstallPrompt(prompt)

        // If parsing failed, show error
        if case .failed(let error) = service.phase {
            postSystem("❌ \(error)", sessionId: sessionId)
        }
        // If successful, the InstallPlanReviewSheet is triggered by ChatWindow observing service.phase
    }

    /// Execute an approved install plan, showing progress in the chat.
    func executeInstallPlan(_ plan: AgentInstallPlan) async {
        let appState = AppState.shared
        let sessionId = overrideSessionId ?? appState.currentSessionId ?? "main"

        // Create assistant message with install progress view
        let progressMessage = ChatMessage(
            role: .assistant,
            content: "",
            sessionId: sessionId,
            providerId: appState.currentCLI?.id,
            installPlanId: plan.id
        )
        messages.append(progressMessage)

        // Execute
        let service = AgentInstallService.shared
        await service.executePlan(plan)

        // Post summary
        if case .completed(let record) = service.phase {
            let completed = record.steps.filter { $0.status == .completed }.count
            let total = record.steps.count
            let failed = record.steps.filter { $0.status == .failed || $0.status == .denied }.count

            if failed == 0 {
                postSystem(String(localized: "Installation completed successfully.", bundle: .module) + " (\(completed)/\(total))", sessionId: sessionId)
            } else {
                postSystem("⚠️ " + String(localized: "Installation finished with issues.", bundle: .module) + " (\(completed)/\(total) " + String(localized: "steps completed", bundle: .module) + ")", sessionId: sessionId)
            }
        }

        persistCurrentSession()
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

        // Combine prompts (skip interactive prompts for local/small models that misuse them)
        let supportsInteractivePrompts = !["ollama", "bitnet"].contains(provider.id)
        let interactiveInstruction = appState.planModeActive || !supportsInteractivePrompts ? nil : interactivePromptInstruction()
        let combinedPrompt: String? = [projectSystemPrompt, skillsPrompt, interactiveInstruction]
            .compactMap { $0 }
            .joined(separator: "\n\n")
            .isEmpty == true ? nil : [projectSystemPrompt, skillsPrompt, interactiveInstruction]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        // Resolve model: per-message override → user default → CLI default
        let resolvedModel = appState.chatModelOverride ?? appState.defaultModels[provider.id]
        appState.chatModelOverride = nil

        let planMode = appState.planModeActive
        let streamStartTime = Date()

        let stream = await CLIBridge.shared.send(
            message: message,
            provider: provider,
            model: resolvedModel,
            sessionId: sessionId,
            isResume: isResume,
            systemPrompt: combinedPrompt,
            planMode: planMode
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

            // Check for interactive prompts in the AI response (skip in plan mode — read-only)
            if !hasError && !planMode {
                let (cleanText, prompts) = InteractivePromptKit.extractPrompts(from: assistantMessage.content)
                if !prompts.isEmpty {
                    assistantMessage.content = cleanText
                    assistantMessage.interactivePrompts = prompts
                    self.updateLastMessage(assistantMessage)

                    // Suspend until user responds to all prompts
                    let promptService = InteractivePromptService.shared
                    let responses = await promptService.presentPrompts(prompts)
                    assistantMessage.promptResponses = responses
                    self.updateLastMessage(assistantMessage)
                    promptService.reset()

                    // Inject answers and continue conversation
                    let answersText = zip(prompts, responses).map { prompt, resp in
                        InteractivePromptKit.formatResponse(resp, prompt: prompt)
                    }.joined(separator: "\n")

                    self.logger.info("Interactive prompts answered (\(prompts.count)), continuing conversation")
                    await self.streamAndEnrich(
                        message: answersText,
                        originalText: originalText,
                        attachments: [],
                        provider: provider,
                        sessionId: sessionId,
                        fetchRound: fetchRound
                    )
                    return
                }
            }

            // Check for @fetch commands in the AI response (skip in plan mode and local models)
            let providerSupportsEnrichment = !["ollama", "bitnet"].contains(provider.id)
            if !hasError && !planMode && providerSupportsEnrichment &&
               ConnectorsKit.containsFetchCommand(assistantMessage.content) &&
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

            // Check for @git() commands in the AI response (skip for local models)
            if !hasError && !planMode && providerSupportsEnrichment && gitContext != nil &&
               assistantMessage.content.contains("@git(") &&
               fetchRound < ConnectorsKit.maxFetchRoundsPerTurn {
                let (cleanResponse, gitResults) = await self.enrichmentService.parseAndExecuteGit(
                    response: assistantMessage.content,
                    repoPath: gitContext?.localPath,
                    round: fetchRound
                )

                if let gitResults {
                    assistantMessage.content = cleanResponse
                    assistantMessage.isStreaming = false
                    self.updateLastMessage(assistantMessage)

                    self.logger.info("@git round \(fetchRound): re-sending with git data")
                    await self.streamAndEnrich(
                        message: gitResults,
                        originalText: originalText,
                        attachments: attachments,
                        provider: provider,
                        sessionId: sessionId,
                        fetchRound: fetchRound + 1
                    )
                    return
                }
            }

            // Check for @git-confirm() and @fetch-confirm() in the AI response (skip for local models)
            if !hasError && !planMode && providerSupportsEnrichment {
                let gitConfirmations = self.enrichmentService.detectGitConfirmations(in: assistantMessage.content)
                let fetchConfirmations = self.enrichmentService.detectFetchConfirmations(in: assistantMessage.content)
                let allConfirmations = gitConfirmations + fetchConfirmations

                if !allConfirmations.isEmpty {
                    assistantMessage.content = self.enrichmentService.removeConfirmationCommands(from: assistantMessage.content)
                    assistantMessage.gitActions = allConfirmations
                    self.updateLastMessage(assistantMessage)
                    self.logger.info("Detected \(allConfirmations.count) git/fetch confirmation(s)")
                    // Do NOT block — cards render inline and user confirms/cancels asynchronously
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
                    self.lastUsedProviderId = fallback.id
                    self.logger.info("Failover: \(provider.id) → \(fallback.id)")

                    // Build the message for the fallback provider (re-enrich with context)
                    var fallbackMessage = originalText
                    if let ctx = self.gitContext {
                        let gitHeader = self.enrichmentService.buildGitContextHeader(ctx)
                        fallbackMessage = "\(gitHeader)\n\n\(fallbackMessage)"
                    }
                    if let header = self.enrichmentService.buildConnectorsHeader() {
                        fallbackMessage = "\(header)\n\n\(fallbackMessage)"
                    }

                    // Call streamAndEnrich directly to avoid duplicating the user message
                    await self.streamAndEnrich(
                        message: fallbackMessage,
                        originalText: originalText,
                        attachments: attachments,
                        provider: fallback,
                        sessionId: sessionId,
                        fetchRound: 1
                    )
                    return
                }
            }

            // Plan Mode: detect plan file and store its path (shown as card in UI)
            if planMode && !hasError {
                if let planFile = self.detectLatestPlanFile(for: provider.id, since: streamStartTime) {
                    assistantMessage.planFilePath = planFile.path
                    self.updateLastMessage(assistantMessage)

                    // Auto-save artifact to project, or prompt user to save
                    let projectId = self.sessionStore.sessions.first(where: { $0.id == sessionId })?.projectId
                    if let projectId {
                        let sourceURL = URL(fileURLWithPath: planFile.path)
                        ProjectArtifactStore.shared.addArtifact(
                            from: sourceURL,
                            fileName: planFile.name,
                            type: .plan,
                            sourceCLI: provider.id,
                            sourceSessionId: sessionId,
                            toProject: projectId
                        )
                    } else {
                        self.pendingArtifactSave = PendingArtifactSave(
                            filePath: planFile.path,
                            fileName: planFile.name,
                            sourceCLI: provider.id,
                            sessionId: sessionId
                        )
                    }
                }
            }

            // Auto-save session after streaming completes
            self.persistCurrentSession()

            // Schedule deferred memory update (fires after 10 min idle or on chat switch)
            self.scheduleMemoryUpdate(sessionId: sessionId)
        }
    }

    // MARK: - Deferred Memory Update (idle timer + chat switch)

    /// Timer that fires after 10 minutes of inactivity to update project memory.
    private var memoryIdleTimer: Task<Void, Never>?
    /// The project ID that has pending memory updates.
    private var pendingMemoryProjectId: String?

    /// Schedule a deferred memory update. Resets the 10-min idle timer on each message.
    /// The update fires when: (a) 10 min idle, or (b) user switches away from this chat.
    private func scheduleMemoryUpdate(sessionId: String) {
        let appState = AppState.shared
        guard appState.memoryProviderId != nil,
              appState.projectMemoryAutoUpdate else { return }

        // Find the project for this session
        let projectId = findProjectId(for: sessionId)
        guard let projectId else { return }

        pendingMemoryProjectId = projectId

        // Cancel previous timer, start fresh 10-min countdown
        memoryIdleTimer?.cancel()
        memoryIdleTimer = Task {
            try? await Task.sleep(for: .seconds(600)) // 10 minutes
            guard !Task.isCancelled else { return }
            await self.flushMemoryUpdate()
        }
    }

    /// Immediately flush pending memory update (called on chat switch or manual trigger).
    func flushMemoryUpdate() async {
        guard let projectId = pendingMemoryProjectId else { return }
        pendingMemoryProjectId = nil
        memoryIdleTimer?.cancel()
        memoryIdleTimer = nil

        let appState = AppState.shared
        guard appState.memoryProviderId != nil,
              appState.projectMemoryAutoUpdate else { return }

        let currentMessages = self.messages
        logger.info("Flushing deferred memory update for project \(projectId)")
        Task.detached {
            await ProjectMemoryStore.shared.updateMemoryAsync(
                for: projectId,
                chatMessages: currentMessages
            )
        }
    }

    /// Find the project ID a session belongs to.
    private func findProjectId(for sessionId: String) -> String? {
        if let info = SessionStore.shared.sessions.first(where: { $0.id == sessionId }) {
            return info.projectId
        }
        return ProjectStore.shared.projects.first(where: { $0.sessionIds.contains(sessionId) })?.id
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

    // MARK: - Git Action Confirmation

    /// Confirm and execute a pending git/platform action.
    func confirmGitAction(messageId: UUID, actionId: UUID) {
        // Check chain depth to prevent infinite loops
        chainDepth += 1
        if chainDepth > Self.maxChainDepth {
            logger.warning("Max chain depth (\(Self.maxChainDepth)) reached, stopping multi-step chain")
            let systemMsg = ChatMessage(
                role: .system,
                content: String(localized: "git_chain_depth_exceeded", bundle: .module),
                sessionId: "main"
            )
            messages.append(systemMsg)
            chainDepth = 0
            return
        }

        guard let msgIdx = messages.firstIndex(where: { $0.id == messageId }),
              let actIdx = messages[msgIdx].gitActions.firstIndex(where: { $0.id == actionId }) else {
            logger.warning("confirmGitAction: message or action not found")
            return
        }

        // Set executing state
        messages[msgIdx].gitActions[actIdx].status = .executing

        let action = messages[msgIdx].gitActions[actIdx]
        let sessionId = messages[msgIdx].sessionId

        Task {
            var output: String
            var success = true

            switch action.type {
            case .localGit:
                guard let repoPath = gitContext?.localPath else {
                    messages[msgIdx].gitActions[actIdx].status = .failed(error: "No local repository path")
                    return
                }
                do {
                    output = try await GitService.shared.executeRaw(command: action.command, repoPath: repoPath)
                    if output.isEmpty { output = "(no output)" }
                } catch {
                    output = error.localizedDescription
                    success = false
                }

            case .platformAPI:
                // Parse connector.action from command
                let parts = action.command.split(separator: ".", maxSplits: 1)
                guard parts.count == 2 else {
                    messages[msgIdx].gitActions[actIdx].status = .failed(error: "Invalid action format: \(action.command)")
                    return
                }
                let connectorName = String(parts[0])
                let actionName = String(parts[1])

                // Resolve connector instance
                guard let instance = ConnectorStore.shared.connectedInstances.first(where: {
                    $0.definitionId.lowercased().contains(connectorName.lowercased())
                }) else {
                    messages[msgIdx].gitActions[actIdx].status = .failed(error: "No connected connector for '\(connectorName)'")
                    return
                }

                do {
                    let result = try await ConnectorExecutor.shared.execute(
                        instanceId: instance.id,
                        actionId: actionName,
                        params: action.details.filter { $0.key != "warning" }
                    )
                    output = result.data
                } catch {
                    output = error.localizedDescription
                    success = false
                }
            }

            // Update action status
            if success {
                messages[msgIdx].gitActions[actIdx].status = .completed(output: output)
            } else {
                messages[msgIdx].gitActions[actIdx].status = .failed(error: output)
            }

            // Send result back to AI for continuation
            let resultMessage: String
            if success {
                resultMessage = "[Git Result] \(action.title) completed.\nOutput: \(output)"
            } else {
                resultMessage = "[Git Result] \(action.title) failed: \(output)"
            }

            logger.info("Git action \(action.title) \(success ? "completed" : "failed"), sending result to AI")

            // Continue the conversation with the result
            guard let provider = AppState.shared.currentCLI else { return }
            await streamAndEnrich(
                message: resultMessage,
                originalText: resultMessage,
                attachments: [],
                provider: provider,
                sessionId: sessionId,
                fetchRound: 1
            )
        }
    }

    /// Cancel a pending git/platform action.
    func cancelGitAction(messageId: UUID, actionId: UUID) {
        guard let msgIdx = messages.firstIndex(where: { $0.id == messageId }),
              let actIdx = messages[msgIdx].gitActions.firstIndex(where: { $0.id == actionId }) else {
            logger.warning("cancelGitAction: message or action not found")
            return
        }

        let action = messages[msgIdx].gitActions[actIdx]
        messages[msgIdx].gitActions[actIdx].status = .cancelled

        let sessionId = messages[msgIdx].sessionId

        // Inform AI about cancellation
        Task {
            guard let provider = AppState.shared.currentCLI else { return }
            let cancellationMessage = "[Git Action Cancelled] User declined: \(action.command)"
            await streamAndEnrich(
                message: cancellationMessage,
                originalText: cancellationMessage,
                attachments: [],
                provider: provider,
                sessionId: sessionId,
                fetchRound: 1
            )
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

        // Take last 20 messages max, truncate long ones to 2000 chars
        let recent = relevant.suffix(20)
        var lines: [String] = ["[Previous conversation context]"]
        for msg in recent {
            let role = msg.role == .user ? "User" : "Assistant"
            let via = msg.providerId.map { " (via \($0))" } ?? ""
            let content = msg.content.prefix(2000)
            let truncated = msg.content.count > 2000 ? "..." : ""
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

        // 0.5 Filesystem instruction — varies based on whether directories are configured
        if !project.directories.isEmpty {
            parts.append("IMPORTANT: This conversation belongs to the project described above. Focus all your answers on this project's topic and goals. Use the project directories listed below as your working paths.")
            parts.append("")
            parts.append("# Project Directories")
            for dir in project.directories {
                parts.append("- \(dir)")
            }
        } else {
            parts.append("IMPORTANT: This conversation belongs to the project described above. Focus all your answers on this project's topic and goals. Do NOT explore or reference the local filesystem — the working directory is unrelated to this project. Use only the project context provided here (rules, files, previous conversations).")
        }

        // 1. Project Memory (single source of truth if it exists — includes description, rules, decisions)
        if let memoryContent = ProjectMemoryStore.shared.loadMemory(for: projectId),
           !memoryContent.isEmpty {
            parts.append("")
            parts.append("# Project Memory")
            parts.append("This is the accumulated project knowledge including description, rules, and decisions from previous conversations.")
            parts.append("")
            parts.append(memoryContent)
        } else {
            // Fallback: inject rules directly (no memory yet)
            if !project.rules.isEmpty {
                parts.append("")
                parts.append("# Project Rules")
                parts.append(project.rules)
            }
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

    /// System prompt instruction that teaches the AI to emit interactive prompts.
    private func interactivePromptInstruction() -> String {
        """
        When you need the user to choose between options or confirm an action, \
        emit a JSON code block with this exact format:
        ```json
        {"type":"interactive_prompt","id":"unique-id","title":"Your question",\
        "options":[{"key":"1","label":"Option 1"},{"key":"2","label":"Option 2"}],\
        "style":"single_choice","required":false}
        ```
        Available styles: single_choice, multi_choice, confirmation, free_text.
        For yes/no confirmations use style "confirmation" (no options needed).
        IMPORTANT: When you need to ask MULTIPLE questions, emit ALL prompts in a SINGLE \
        JSON array code block. Do NOT send one prompt per response — that causes loops. Example:
        ```json
        [
          {"type":"interactive_prompt","id":"q1","title":"First question","style":"single_choice",\
        "options":[{"key":"a","label":"A"},{"key":"b","label":"B"}]},
          {"type":"interactive_prompt","id":"q2","title":"Second question","style":"free_text"},
          {"type":"interactive_prompt","id":"q3","title":"Confirm?","style":"confirmation"}
        ]
        ```
        The app renders these as a wizard with Next/Back navigation. \
        Do NOT repeat the options as plain text. Do NOT send prompts one at a time.
        """
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

    // MARK: - Plan File Detection

    /// Detect the most recently created plan file for a CLI provider since a given timestamp.
    private func detectLatestPlanFile(for providerId: String, since: Date) -> (path: String, name: String)? {
        let fm = FileManager.default

        // Plan file directories per provider
        let planDirs: [String]
        switch providerId {
        case "claude":
            let home = fm.homeDirectoryForCurrentUser.path
            planDirs = ["\(home)/.claude/plans"]
        case "gemini":
            // Gemini stores plans in the working directory or ~/.gemini/plans
            let home = fm.homeDirectoryForCurrentUser.path
            planDirs = ["\(home)/.gemini/plans"]
        default:
            return nil // Other providers don't create plan files
        }

        var latestFile: (path: String, name: String, date: Date)?

        for dir in planDirs {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in contents where file.hasSuffix(".md") {
                let fullPath = "\(dir)/\(file)"
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                      let modDate = attrs[.modificationDate] as? Date,
                      modDate > since else { continue }

                if latestFile == nil || modDate > latestFile!.date {
                    latestFile = (path: fullPath, name: file, date: modDate)
                }
            }
        }

        guard let result = latestFile else { return nil }
        return (path: result.path, name: result.name)
    }

    // MARK: - Slash Commands

    /// Process a slash command. Returns true if the command was handled.
    private func handleSlashCommand(_ input: String) -> Bool {
        let parts = input.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0].lowercased()
        let argument = parts.count > 1 ? parts[1] : nil
        let appState = AppState.shared
        let sessionId = overrideSessionId ?? appState.currentSessionId ?? "main"

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
                if var loaded = sessionStore.load(sessionId: name) {
                    for i in loaded.indices {
                        loaded[i].isStreaming = false
                        loaded[i].isGeneratingImage = false
                    }
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

        case "/install":
            if let installArg = argument, !installArg.isEmpty {
                if installArg == "list" {
                    let registry = AgentInstallService.shared.installRegistry
                    if registry.isEmpty {
                        postSystem(String(localized: "No packages installed yet.", bundle: .module), sessionId: sessionId)
                    } else {
                        var listing = "**" + String(localized: "Installed Packages", bundle: .module) + "**\n"
                        for record in registry.suffix(10) {
                            let date = record.installedAt.formatted(date: .abbreviated, time: .shortened)
                            let steps = record.steps.filter { $0.status == .completed }.count
                            listing += "- **\(record.name)** — \(steps) steps — \(date)\n"
                        }
                        postSystem(listing, sessionId: sessionId)
                    }
                } else {
                    Task { await sendInstallPrompt(installArg) }
                }
            } else {
                postSystem("Usage: `/install <prompt>` — Parse an install prompt and create an execution plan.\n`/install list` — Show installed packages.", sessionId: sessionId)
            }
            return true

        case "/copy":
            // Copy last assistant message to clipboard
            if let lastAssistant = messages.last(where: { $0.role == .assistant }) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lastAssistant.content, forType: .string)
                postSystem(String(localized: "Last response copied to clipboard.", bundle: .module), sessionId: sessionId)
            } else {
                postSystem(String(localized: "No assistant response to copy.", bundle: .module), sessionId: sessionId)
            }
            return true

        case "/diff":
            // Run git diff and show result
            Task {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    process.arguments = ["diff", "--stat"]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if output.isEmpty {
                        postSystem(String(localized: "No uncommitted changes.", bundle: .module), sessionId: sessionId)
                    } else {
                        postSystem("```\n\(output)\n```", sessionId: sessionId)
                    }
                } catch {
                    postSystem(String(localized: "Failed to run git diff.", bundle: .module), sessionId: sessionId)
                }
            }
            return true

        case "/plan":
            appState.planModeActive.toggle()
            let state = appState.planModeActive
                ? String(localized: "Plan Mode enabled — read-only analysis.", bundle: .module)
                : String(localized: "Plan Mode disabled.", bundle: .module)
            postSystem(state, sessionId: sessionId)
            return true

        case "/export":
            // Export conversation to a text file
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "mcclaw-chat-\(sessionId.prefix(8)).txt"
            guard panel.runModal() == .OK, let url = panel.url else {
                return true
            }
            var export = ""
            for msg in messages {
                let role = msg.role.rawValue.uppercased()
                export += "[\(role)] \(msg.content)\n\n"
            }
            do {
                try export.write(to: url, atomically: true, encoding: .utf8)
                postSystem(String(localized: "Chat exported to: ", bundle: .module) + url.lastPathComponent, sessionId: sessionId)
            } catch {
                postSystem(String(localized: "Failed to export chat.", bundle: .module), sessionId: sessionId)
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
            - `/install <prompt>` — Parse and execute an install prompt
            - `/copy` — Copy last response to clipboard
            - `/diff` — Show git changes summary
            - `/plan` — Toggle Plan Mode
            - `/export` — Export chat to file
            - `/help` — Show this help

            *Type `/` to see autocomplete suggestions. Commands starting with `/` that McClaw doesn't recognize are passed to the active CLI.*
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
        let sessionId = overrideSessionId ?? appState.currentSessionId
        guard let sessionId, !messages.isEmpty else { return }
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
              var loaded = sessionStore.load(sessionId: sessionId) else { return }
        // Clear stale streaming flags from persisted messages
        for i in loaded.indices {
            loaded[i].isStreaming = false
            loaded[i].isGeneratingImage = false
        }
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

    // MARK: - Git Session Persistence

    /// Save messages for a specific Git session (independent of AppState.currentSessionId).
    func persistGitSession(sessionId: String) {
        let meaningful = messages.filter { $0.role == .user || $0.role == .assistant }
        guard !meaningful.isEmpty else { return }
        let provider = AppState.shared.currentCLI?.id
        sessionStore.save(sessionId: sessionId, messages: messages, provider: provider)
        logger.info("Git session saved: \(sessionId) (\(messages.count) messages)")
    }

    /// Load messages for a specific Git session (independent of AppState.currentSessionId).
    func loadGitSession(sessionId: String) {
        guard var loaded = sessionStore.load(sessionId: sessionId) else { return }
        // Clear stale streaming flags from persisted messages
        for i in loaded.indices {
            loaded[i].isStreaming = false
            loaded[i].isGeneratingImage = false
        }
        messages = loaded
        overrideSessionId = sessionId

        // Rebuild provider tracking
        let meaningful = loaded.filter { $0.role == .user || $0.role == .assistant }
        providersUsedInSession = Set(meaningful.compactMap(\.providerId))
        if !meaningful.isEmpty, providersUsedInSession.isEmpty,
           let currentCLI = AppState.shared.currentCLIIdentifier {
            providersUsedInSession.insert(currentCLI)
        }
        needsContextInjection = !meaningful.isEmpty
        logger.info("Git session loaded: \(sessionId) (\(loaded.count) messages)")
    }
}
