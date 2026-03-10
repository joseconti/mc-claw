# McClaw - Chat Interface and UI

## 1. UI Overview

McClaw is a menu bar app with multiple visual surfaces:

```
+-- Menu Bar ------------------------------------------------+
|  [McClaw Icon] [Status: idle/working/voice]                |
+------------------------------------------------------------+

+-- Dropdown Menu -------------------------------------------+
|  Status: Claude Sonnet 4.6 - idle                          |
|  ------------------------------------------------          |
|  Sessions:                                                 |
|    Main - 0 messages                                       |
|    WhatsApp:+34... - 12 messages                           |
|  ------------------------------------------------          |
|  Usage: 1,234 tokens | $0.02                               |
|  ------------------------------------------------          |
|  [Open Chat] [Canvas] [Settings] [Pause/Resume]            |
|  ------------------------------------------------          |
|  Health: OK | Gateway: running                             |
|  ------------------------------------------------          |
|  [Quit McClaw]                                             |
+------------------------------------------------------------+
```

---

## 2. Menu Bar

### 2.1 Status Icon (CritterStatusLabel)

The menu bar icon is an animated "critter" that reflects the current state:

```swift
enum IconState: Equatable {
    case idle                              // Normal critter, occasional blinking
    case workingMain(ActivityKind)          // Badge with glyph, full tint, animation
    case workingOther(ActivityKind)         // Badge with glyph, dimmed tint
    case overridden(ActivityKind)           // Debug override
}

enum ActivityKind: String {
    case exec       // Command execution
    case read       // File read
    case write      // File write
    case edit       // File edit
    case attach     // Attachment/media
    case general    // Generic activity
}
```

**Visualization**:
- **Idle**: normal critter with blinking and subtle movement
- **Working (main)**: badge with activity glyph, "legs" animation, full tint
- **Working (other)**: badge with glyph, dimmed tint, no running animation
- **Voice active**: enlarged ears (1.9x), circular nostrils
- **Paused**: `appearsDisabled`, no movement

**Rendering**: `CritterIconRenderer.makeIcon(blink:legWiggle:earWiggle:earScale:earHoles:)`
- Frame: 18x18pt (36x36px on Retina)
- Short TTLs (<10s) so the icon returns to baseline if something hangs

### 2.2 Context Menu

```swift
struct MenuContentView: View {
    @State var appState: AppState
    @State var healthStore: HealthStore
    @State var workActivity: WorkActivityStore

    var body: some View {
        VStack {
            // Header with state
            MenuHeaderCard(state: appState)

            // Active sessions
            MenuSessionsHeaderView()

            // Usage/cost
            MenuUsageHeaderView()

            Divider()

            // Quick actions
            Button("Open Chat") { WebChatManager.shared.showWindow() }
            Button("Canvas") { CanvasManager.shared.show(sessionKey: "main") }

            Divider()

            // Controls
            Toggle("Pause", isOn: $appState.isPaused)
            Toggle("Voice Wake", isOn: $appState.voiceWakeEnabled)
            Toggle("Talk Mode", isOn: $appState.talkModeEnabled)

            Divider()

            // Health
            HealthStatusView(store: healthStore)

            Divider()

            // Settings and Quit
            Button("Settings...") { SettingsWindowOpener.open() }
            Button("Quit McClaw") { NSApp.terminate(nil) }
        }
    }
}
```

### 2.3 Menu Bar State (text)

- While working: `<Session> - <activity>` (e.g.: "Main - exec: swift test")
- When idle: Gateway health summary

---

## 3. Chat Window (WebChat)

### 3.1 Architecture

```swift
@MainActor
class WebChatManager {
    static let shared = WebChatManager()

    private var windowController: WebChatSwiftUIWindowController?

    // Show as window
    func showWindow() {
        if windowController == nil {
            windowController = WebChatSwiftUIWindowController()
        }
        windowController?.showWindow(nil)
    }

    // Show as panel (anchored to menu bar)
    func showPanel(anchor: NSPoint) {
        windowController?.showAsPanel(near: anchor)
    }
}
```

### 3.2 Main Chat View

```swift
struct ChatView: View {
    @State var viewModel: ChatViewModel
    @State var inputText: String = ""
    @FocusState var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Session selector
            SessionPickerView(
                sessions: viewModel.sessions,
                selected: $viewModel.currentSession
            )

            // Message area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        // Typing indicator
                        if viewModel.isTyping {
                            TypingIndicatorView()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input bar
            ChatInputBar(
                text: $inputText,
                isDisabled: viewModel.isProcessing,
                attachments: $viewModel.pendingAttachments,
                onSend: { viewModel.send(inputText); inputText = "" },
                onAbort: { viewModel.abort() }
            )
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}
```

### 3.3 Chat ViewModel

```swift
@MainActor
@Observable
class ChatViewModel {
    // State
    var messages: [ChatMessage] = []
    var currentSession: SessionKey = .main
    var sessions: [SessionInfo] = []
    var isProcessing: Bool = false
    var isTyping: Bool = false
    var pendingAttachments: [URL] = []

    // Services
    private let gateway: GatewayConnection
    private let cliBridge: CLIBridge
    private let sessionManager: SessionManager

    // Send message
    func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text, attachments: pendingAttachments)
        messages.append(userMessage)
        pendingAttachments = []
        isProcessing = true

        Task {
            do {
                // Via Gateway if there's an active channel, or via CLI directly
                if currentSession.isChannelBound {
                    try await gateway.chatSend(text, session: currentSession)
                } else {
                    let response = try await cliBridge.send(
                        message: text,
                        provider: AppState.shared.currentCLI!,
                        options: buildChatOptions(),
                        onPartial: { [weak self] chunk in
                            Task { @MainActor in
                                self?.handlePartial(chunk)
                            }
                        },
                        onToolUse: { [weak self] event in
                            Task { @MainActor in
                                self?.handleToolUse(event)
                            }
                        },
                        onComplete: { [weak self] response in
                            Task { @MainActor in
                                self?.handleComplete(response)
                            }
                        }
                    )
                }
            } catch {
                handleError(error)
            }
        }
    }

    // Abort
    func abort() {
        Task {
            await cliBridge.abort()
            // Or via Gateway:
            try? await gateway.chatAbort(session: currentSession)
        }
        isProcessing = false
    }

    // Process partial response (streaming)
    private func handlePartial(_ chunk: String) {
        if let last = messages.last, last.role == .assistant, last.isStreaming {
            messages[messages.count - 1].content += chunk
        } else {
            let msg = ChatMessage(role: .assistant, content: chunk, isStreaming: true)
            messages.append(msg)
        }
    }

    // Process tool use
    private func handleToolUse(_ event: ToolUseEvent) {
        let toolMessage = ChatMessage(
            role: .tool,
            toolName: event.name,
            toolPhase: event.phase,
            content: event.phase == .start
                ? "Running: \(event.name)"
                : event.result ?? ""
        )
        messages.append(toolMessage)
    }

    // Completed
    private func handleComplete(_ response: CLIResponse) {
        if let last = messages.last, last.role == .assistant, last.isStreaming {
            messages[messages.count - 1].isStreaming = false
        }
        isProcessing = false
    }
}
```

### 3.4 Message Bubbles

```swift
struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Content by type
                switch message.role {
                case .user:
                    UserMessageContent(message: message)

                case .assistant:
                    AssistantMessageContent(message: message)

                case .tool:
                    ToolCallCard(message: message)

                case .system:
                    SystemMessageView(message: message)
                }

                // Timestamp
                Text(message.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(message.role == .user
                ? Color.accentColor.opacity(0.15)
                : Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role != .user {
                Spacer()
            }
        }
    }
}
```

### 3.5 Markdown Rendering

```swift
struct AssistantMessageContent: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Markdown with support for:
            // - Formatted text (bold, italic, strikethrough)
            // - Code blocks with syntax highlighting
            // - Lists (ordered and unordered)
            // - Clickable links
            // - Inline images
            // - Tables
            // - Block quotes
            MarkdownView(content: message.content)

            // Streaming indicator
            if message.isStreaming {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Usage info (if available)
            if let usage = message.usage {
                UsageBadge(usage: usage)
            }
        }
    }
}
```

### 3.6 Tool Cards

```swift
struct ToolCallCard: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: toolIcon(message.toolName ?? ""))
                Text(message.toolName ?? "Tool")
                    .font(.caption.bold())
                Spacer()
                if message.toolPhase == .start {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let content = message.content, !content.isEmpty {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func toolIcon(_ name: String) -> String {
        switch name {
        case "exec", "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "square.and.pencil"
        case "edit": return "pencil"
        case "browser": return "globe"
        case "canvas": return "paintbrush"
        default: return "wrench"
        }
    }
}
```

### 3.7 Input Bar

```swift
struct ChatInputBar: View {
    @Binding var text: String
    let isDisabled: Bool
    @Binding var attachments: [URL]
    let onSend: () -> Void
    let onAbort: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            // Attachment previews
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(attachments, id: \.self) { url in
                            AttachmentPreview(url: url) {
                                attachments.removeAll { $0 == url }
                            }
                        }
                    }
                }
                .frame(height: 60)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Attach button
                Button(action: { pickAttachment() }) {
                    Image(systemName: "paperclip")
                }

                // Expandable text field
                TextEditor(text: $text)
                    .frame(minHeight: 36, maxHeight: isExpanded ? 200 : 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separatorColor))
                    )
                    .onSubmit { if !text.isEmpty { onSend() } }

                // Send/cancel button
                if isDisabled {
                    Button(action: onAbort) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                    }
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.accentColor)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
```

---

## 4. Chat Commands

Commands the user can type directly in the chat:

```swift
enum ChatCommand: String, CaseIterable {
    case status     = "/status"      // Session status
    case new        = "/new"         // New session
    case reset      = "/reset"       // Reset session
    case compact    = "/compact"     // Compact context
    case think      = "/think"       // Thinking level
    case verbose    = "/verbose"     // Verbose mode
    case usage      = "/usage"       // Usage info
    case model      = "/model"       // Change model
    case cli        = "/cli"         // Change active CLI
    case activation = "/activation"  // Group activation toggle

    var description: String {
        switch self {
        case .status: return "Compact session status (model + tokens)"
        case .new, .reset: return "Reset the current session"
        case .compact: return "Compact the context (summary)"
        case .think: return "Level: off|minimal|low|medium|high|xhigh"
        case .verbose: return "on|off"
        case .usage: return "off|tokens|full"
        case .model: return "Change active model"
        case .cli: return "Change active CLI (claude, chatgpt, etc.)"
        case .activation: return "mention|always (groups only)"
        }
    }
}
```

---

## 5. Settings Window

### 5.1 Tab Structure

```swift
enum SettingsTab: String, CaseIterable {
    case about       = "About"
    case general     = "General"
    case clis        = "CLIs"         // NEW: replaces API key config
    case channels    = "Channels"
    case cron        = "Cron"
    case sessions    = "Sessions"
    case plugins     = "Plugins"
    case skills      = "Skills"
    case permissions = "Permissions"
    case debug       = "Debug"
}
```

### 5.2 CLIs Tab (New)

```swift
struct CLIsSettingsView: View {
    @State var detector: CLIDetector
    @State var scanResults: [CLIDetector.ScanResult] = []
    @State var isScanning = false

    var body: some View {
        Form {
            Section("Detected CLIs") {
                ForEach(scanResults, id: \.provider.id) { result in
                    CLIProviderRow(result: result)
                }
            }

            Section("Default CLI") {
                Picker("Main provider", selection: $appState.defaultCLI) {
                    ForEach(scanResults.filter(\.isAuthenticated)) { result in
                        Text(result.provider.displayName)
                            .tag(result.provider.id)
                    }
                }
            }

            Section("Fallback") {
                Text("Priority order when the main CLI fails:")
                List {
                    // Drag & drop to reorder
                    ForEach($appState.cliFallbackOrder, id: \.self) { $id in
                        Text(id)
                    }
                    .onMove { from, to in
                        appState.cliFallbackOrder.move(fromOffsets: from, toOffset: to)
                    }
                }
            }

            Button("Re-scan CLIs") {
                Task {
                    isScanning = true
                    scanResults = await detector.scan()
                    isScanning = false
                }
            }
        }
    }
}

struct CLIProviderRow: View {
    let result: CLIDetector.ScanResult

    var body: some View {
        HStack {
            // Status icon
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading) {
                Text(result.provider.displayName)
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let path = result.path {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Actions
            switch result.status {
            case .notInstalled:
                Menu("Install") {
                    ForEach(result.provider.installMethods, id: \.description) { method in
                        Button(method.description) {
                            Task { try? await CLIBridge.shared.install(result.provider, method: method) }
                        }
                    }
                }
            case .installedNotAuth:
                Button("Authenticate") { openTerminalWithLogin(result.provider) }
            case .installed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error(let msg):
                Label(msg, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }
}
```

### 5.3 General Tab

```swift
struct GeneralSettingsView: View {
    @State var appState: AppState

    var body: some View {
        Form {
            Section("Connection") {
                Picker("Mode", selection: $appState.connectionMode) {
                    Text("Local (this Mac)").tag(ConnectionMode.local)
                    Text("Remote (SSH)").tag(ConnectionMode.remote)
                }

                if appState.connectionMode == .remote {
                    TextField("SSH Target", text: $appState.remoteTarget)
                    Picker("Transport", selection: $appState.remoteTransport) {
                        Text("SSH Tunnel").tag(RemoteTransport.ssh)
                        Text("Direct (WS)").tag(RemoteTransport.direct)
                    }
                    TextField("Gateway URL", text: $appState.remoteUrl)
                }
            }

            Section("Behavior") {
                Toggle("Launch at login", isOn: $appState.launchAtLogin)
                Toggle("Show in Dock", isOn: $appState.showDockIcon)
                Toggle("Icon animations", isOn: $appState.iconAnimationsEnabled)
                Toggle("Heartbeats", isOn: $appState.heartbeatsEnabled)
            }

            Section("Voice") {
                Toggle("Voice Wake (wake-word)", isOn: $appState.voiceWakeEnabled)
                Toggle("Push-to-Talk (Cmd+Fn)", isOn: $appState.voicePushToTalkEnabled)
                Toggle("Talk Mode (TTS)", isOn: $appState.talkModeEnabled)

                if appState.voiceWakeEnabled {
                    // Trigger words
                    // Microphone selector
                    // Language selector
                    // Level meter
                    // Chime sounds
                }
            }

            Section("Advanced") {
                Toggle("Canvas", isOn: $appState.canvasEnabled)
                Toggle("Peekaboo Bridge", isOn: $appState.peekabooBridgeEnabled)
                Toggle("Debug Panel", isOn: $appState.debugPaneEnabled)
            }
        }
    }
}
```

---

## 6. Onboarding (First Run)

### 6.1 Wizard Flow

```
Page 1: Welcome
    "McClaw - Your personal AI assistant"
    "McClaw works as an interface for official AI CLIs"
    [Continue]

Page 2: CLI Detection
    Automatic scan of installed CLIs
    List of found / not found CLIs
    Install buttons for missing ones
    [Continue] (requires at least 1 CLI installed and authenticated)

Page 3: Default CLI Selection
    Main CLI selector
    Default model selector
    Quick test: "Hello, respond with 'OK'"
    [Continue]

Page 4: macOS Permissions
    Request necessary permissions:
    - Microphone (for Voice Wake)
    - Speech Recognition (for transcription)
    - Notifications
    - Accessibility (optional, for PTT)
    [Continue]

Page 5: Channel Setup (optional)
    "Connect your messaging channels"
    WhatsApp, Telegram, Discord, Slack...
    [Skip] [Configure]

Page 6: Ready
    "McClaw is ready to use"
    Configuration summary
    [Open McClaw]
```

---

## 7. Canvas Panel

### 7.1 Structure

```swift
@MainActor
class CanvasManager {
    static let shared = CanvasManager()

    // Canvas root
    let canvasRoot: URL  // ~/Library/Application Support/McClaw/canvas/

    // Active window
    private var windowController: CanvasWindowController?

    // Custom scheme: mcclaw-canvas://
    func show(sessionKey: String, path: String? = nil, placement: CanvasPlacement? = nil) {
        let url = buildCanvasURL(session: sessionKey, path: path)
        if windowController == nil {
            windowController = CanvasWindowController()
        }
        windowController?.navigate(to: url)
        windowController?.showWindow(nil)
    }

    func hide() {
        windowController?.close()
    }

    func evaluate(js: String) async -> String? {
        await windowController?.webView.evaluateJavaScript(js) as? String
    }

    func snapshot() async -> NSImage? {
        await windowController?.captureSnapshot()
    }
}
```

### 7.2 URL Scheme

```
mcclaw-canvas://<session>/<path>
    -> ~/Library/Application Support/McClaw/canvas/<session>/<path>

Examples:
    mcclaw-canvas://main/           -> .../canvas/main/index.html
    mcclaw-canvas://main/app.css    -> .../canvas/main/app.css
    mcclaw-canvas://main/widgets/   -> .../canvas/main/widgets/index.html
```

### 7.3 A2UI (Agent-to-UI)

The Canvas supports A2UI v0.8 so the agent can render declarative UI:

```swift
// Server -> client messages
enum A2UIMessage {
    case beginRendering(surfaceId: String, root: String)
    case surfaceUpdate(surfaceId: String, components: [A2UIComponent])
    case dataModelUpdate(surfaceId: String, data: [String: Any])
    case deleteSurface(surfaceId: String)
}
```

---

## 8. Voice Overlay

### 8.1 Voice Overlay

```swift
struct VoiceOverlayView: View {
    @State var coordinator: VoiceSessionCoordinator

    var body: some View {
        VStack(spacing: 12) {
            // Transcribed text
            Text(coordinator.currentText)
                .font(.title3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // Partial text (in gray)
            if !coordinator.volatileText.isEmpty {
                Text(coordinator.volatileText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Audio level indicator
            AudioLevelMeter(level: coordinator.audioLevel)

            // Controls
            HStack {
                Button("Cancel") { coordinator.cancel() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Send") { coordinator.sendNow() }
                    .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(width: 400)
    }
}
```

### 8.2 Voice Session Coordinator

```swift
actor VoiceSessionCoordinator {
    // Active session
    private(set) var activeSession: VoiceSession?

    // State published to SwiftUI
    @Published var currentText: String = ""
    @Published var volatileText: String = ""
    @Published var audioLevel: Float = 0
    @Published var isVisible: Bool = false

    // Wake word detected
    func beginWakeCapture(token: UUID) async

    // Push-to-talk started (adopts existing text)
    func beginPushToTalk(token: UUID) async

    // Partial text from recognizer
    func updatePartial(_ text: String, token: UUID) async

    // Capture finished
    func endCapture(token: UUID) async

    // Cancel
    func cancel() async

    // Send now (without waiting for silence)
    func sendNow() async

    // Cooldown after PTT to avoid re-triggering the wake-word
    func applyCooldown() async
}
```
