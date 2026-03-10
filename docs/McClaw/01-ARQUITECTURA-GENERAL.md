# McClaw - General Architecture

## 1. Project Vision

McClaw is a native macOS application (Swift/SwiftUI) that works as a personal AI assistant. Its fundamental difference is that it **does not connect directly to AI provider APIs** (which is not allowed by their TOS), but instead **acts as a graphical interface for the official CLIs** of each provider installed on the user's Mac.

McClaw offers full functionality (multi-channel, voice, canvas, plugins, cron, tools) adapted to a native Mac application with a superior user experience.

---

## 2. Fundamental Architecture

### Traditional approach (direct API)
```
User -> Gateway (Node.js) -> Direct provider API (Anthropic, OpenAI, etc.)
```

### McClaw (CLI Bridge architecture)
```
User -> Native macOS app (Swift) -> Official provider CLI (claude, chatgpt, etc.)
                                  -> External Gateway via WebSocket (channels, plugins, automation)
```

The McClaw app acts as a **UI wrapper** for the official CLIs. This means:

- No direct API keys needed (uses CLI authentication)
- Complies with each provider's TOS
- The user maintains full control over their CLI configuration
- The app detects which CLIs are installed and offers to install missing ones

---

## 3. High-Level Architecture

```
+------------------------------------------------------------------+
|                        McClaw.app (Swift/SwiftUI)                |
|                                                                  |
|  +------------------+  +------------------+  +-----------------+ |
|  |   Menu Bar UI    |  |   Chat Window    |  |   Settings      | |
|  |   (Status Icon)  |  |   (SwiftUI)      |  |   (SwiftUI)     | |
|  +--------+---------+  +--------+---------+  +--------+--------+ |
|           |                     |                     |          |
|  +--------+---------------------+---------------------+--------+ |
|  |                    App State Manager                        | |
|  |              (@Observable, @MainActor, Singleton)           | |
|  +------+--------------------+--------------------+------------+ |
|         |                    |                    |              |
|  +------+-------+  +--------+--------+  +--------+---------+     |
|  | CLI Bridge   |  | Cron Scheduler  |  | Connectors       |     |
|  | (Process/    |  | (LocalScheduler |  | (30+ services,   |     |
|  | stdin/stdout) | |  + claude task) |  | OAuth, Keychain) |     |
|  +------+-------+  +-----------------+  +------------------+     |
|         |                                                        |
+---------|--------------------------------------------------------+
          |
   +------v-----------+
   | Official CLIs    |
   | - claude         |
   | - chatgpt        |
   | - gemini         |
   | - ollama         |
   +------------------+
```

---

## 4. Main Components

### 4.1 Presentation Layer (SwiftUI)

| Component | Description |
|---|---|
| **MenuBar** | Menu bar icon with state (idle, working, voice), context menu, quick access |
| **ChatWindow** | Main chat window with support for markdown, code blocks, images |
| **SettingsWindow** | Tabbed settings: General, CLIs, Channels, Cron, Permissions, Plugins, Debug |
| **CanvasPanel** | Visual panel controlled by the agent (WKWebView with custom scheme) |
| **VoiceOverlay** | Voice overlay for wake-word and push-to-talk |
| **OnboardingWizard** | First-run assistant: CLI detection, initial setup |

### 4.2 Business Logic Layer

| Component | Description |
|---|---|
| **AppState** | Central app state (@Observable, singleton). Manages connection, pause, configuration |
| **CLIBridge** | Engine that executes AI CLI commands and processes stdin/stdout/stderr |
| **GatewayConnection** | WebSocket client for communication with the local Gateway |
| **ControlChannel** | Real-time event streaming from the Gateway |
| **SessionManager** | Chat session management (main, group, cron, subagent) |
| **ContextEngine** | Context engine: message assembly, token budgeting, compaction |

### 4.3 System Services Layer

| Component | Description |
|---|---|
| **VoiceWakeRuntime** | Wake-word detection via Swabble/SFSpeechRecognizer |
| **TalkModeRuntime** | Bidirectional voice conversation (STT + TTS) |
| **CanvasManager** | Canvas panel management and custom URL scheme |
| **NodeMode** | Node mode: exposes macOS capabilities to the Gateway (camera, screen, system.run) |
| **ExecApprovals** | Execution security: allowlist, deny, ask |
| **HealthStore** | Gateway and channel health monitoring |
| **PluginRuntime** | Management UI for Gateway plugins (plugins run externally on the Gateway) |

### 4.4 Infrastructure Layer

| Component | Description |
|---|---|
| **CLIDetector** | Detection of installed CLIs (claude, chatgpt, gemini, ollama, etc.) |
| **CLIInstaller** | Assisted CLI installation via brew/npm/curl |
| **ProcessManager** | Child process management (gateway, CLIs) |
| **ConfigStore** | Configuration persistence (JSON/TOML in ~/.mcclaw/) |
| **LaunchdManager** | LaunchAgent management for the Gateway |
| **FileWatcher** | File change observation (FSEvents) |
| **IPCBridge** | Inter-process communication via Unix socket |

---

## 5. Main Data Flow (Chat)

```
1. User types message in ChatWindow
                    |
2. ChatWindow -> SessionManager.send(message)
                    |
3. SessionManager determines the active provider
                    |
4. CLIBridge.execute(cli: "claude", args: ["--message", text])
   - Spawn Process with stdin/stdout pipes
   - Response stream via stdout
   - Block parsing (text, code, tool-use)
                    |
5. ControlChannel publishes progress events
   - ChatWindow updates UI in real time
   - MenuBar shows "working" state
                    |
6. Response complete -> SessionManager.save(transcript)
   - Persistence to disk
   - Context update
                    |
7. If there is an output channel (WhatsApp, Telegram, etc.):
   GatewayConnection.send(reply, channel)
```

---

## 6. App Startup Flow

```
1. AppDelegate.applicationDidFinishLaunching()
       |
2. Load AppState from UserDefaults + config files
       |
3. CLIDetector.scan() -> detect installed CLIs
       |
4. If first run -> show OnboardingWizard
   - Detect CLIs
   - Offer to install missing ones
   - Set default CLI
   - Configure workspace
       |
5. ConnectionModeCoordinator.apply()
   - Local: start Gateway via launchd
   - Remote: establish SSH tunnel
       |
6. Start services:
   - GatewayConnection (WebSocket)
   - ControlChannel (events)
   - HealthStore (polling every 60s)
   - VoiceWakeRuntime (if enabled)
   - NodeMode (if enabled)
   - PluginRuntime (sync plugin status from Gateway)
   - PeekabooBridge (if enabled)
   - PortGuardian (verify ports)
       |
7. App ready to use
```

---

## 7. State Management

### AppState (Singleton, @Observable, @MainActor)

```swift
@MainActor
@Observable
final class AppState {
    // Connection mode
    var connectionMode: ConnectionMode  // .unconfigured, .local, .remote
    var remoteTransport: RemoteTransport  // .ssh, .direct

    // App state
    var isPaused: Bool
    var isWorking: Bool
    var currentCLI: CLIProvider?
    var availableCLIs: [CLIProvider]

    // Voice
    var voiceWakeEnabled: Bool
    var voicePushToTalkEnabled: Bool
    var talkModeEnabled: Bool
    var triggerWords: [String]

    // UI
    var launchAtLogin: Bool
    var showDockIcon: Bool
    var iconAnimationsEnabled: Bool
    var debugPaneEnabled: Bool

    // Canvas
    var canvasEnabled: Bool

    // Plugins
    var loadedPlugins: [PluginInfo]

    // Remote
    var remoteTarget: String?
    var remoteUrl: String?
    var remoteIdentity: String?
}
```

### Persistence
- **UserDefaults**: UI preferences, toggles, last selection
- **Config files**: `~/.mcclaw/mcclaw.json` (main configuration)
- **Credentials**: `~/.mcclaw/credentials/` (channel tokens)
- **Sessions**: `~/.mcclaw/sessions/` (session transcripts)
- **Workspace**: `~/.mcclaw/workspace/` (skills, AGENTS.md, SOUL.md)

---

## 8. Security Model

### Principles
1. **One user per instance**: McClaw is a personal assistant, not multi-tenant
2. **CLI as authentication layer**: authentication is managed by each official CLI
3. **Exec approvals**: system commands require explicit approval
4. **Sandbox by default**: non-main sessions run in a sandbox (Docker if available)
5. **Secure IPC**: Unix sockets with UID verification, HMAC, TTL
6. **TCC respected**: all sensitive operations go through macOS permissions

### Trust Levels
- **Trusted operator**: the authenticated user on the Mac
- **Untrusted agent**: the AI model (assume prompt injection is possible)
- **Trusted plugins**: installed by the operator, run with their privileges
- **Untrusted web content**: all external content requires verification

---

## 9. System Requirements

| Requirement | Detail |
|---|---|
| **macOS** | 15.0 (Sequoia) or later |
| **Xcode** | 16.2+ for building |
| **Swift** | 6.2 |
| **Node.js** | 22+ (for the Gateway) |
| **At least one AI CLI** | claude, chatgpt, gemini, ollama, or similar |

---

## 10. Project Directory Structure

```
McClaw/
  Package.swift
  Sources/
    McClaw/                    # Main app
      App/                     # Entry point, AppDelegate, MenuBar
      State/                   # AppState, Stores
      Views/                   # SwiftUI views
        Chat/                  # Chat window, message bubbles
        Settings/              # Settings tabs
        Onboarding/            # First-run wizard
        Canvas/                # Canvas panel
        Voice/                 # Voice overlay
        Menu/                  # Menu bar content
      Services/                # Business logic
        CLIBridge/             # CLI execution engine
        Gateway/               # WebSocket client
        Voice/                 # Wake word, PTT, Talk mode
        Canvas/                # Canvas management
        Node/                  # Node mode
        Plugins/               # Plugin runtime
        Security/              # Exec approvals, permissions
        Health/                # Health monitoring
      Infrastructure/          # Low-level utilities
        Process/               # Process management
        IPC/                   # Inter-process communication
        Config/                # Configuration management
        FileWatcher/           # FSEvents wrappers
        Logging/               # OSLog structured logging
        Launchd/               # LaunchAgent management
      Models/                  # Data models
        Chat/                  # Message, Session, Transcript
        Gateway/               # Protocol types
        CLI/                   # CLI provider types
        Plugin/                # Plugin types
      Resources/               # Assets, icons, sounds
    McClawIPC/                 # IPC protocol library
    McClawDiscovery/           # Gateway discovery library
    McClawProtocol/            # Generated protocol models
    McclawCLI/                 # CLI companion tool
  Tests/
    McClawTests/
  Swabble/                     # Voice wake word (SPM dependency)
```

---

## 11. External Dependencies (Swift Package Manager)

| Package | Version | Purpose |
|---|---|---|
| **MenuBarExtraAccess** | 1.2.2+ | Menu bar control |
| **swift-log** | latest | Structured logging |
| **Sparkle** | 2.8.1+ | Auto-updates |

**Internal SPM targets** (not external dependencies):

| Target | Purpose |
|---|---|
| **McClaw** | Main executable app |
| **McClawKit** | Core pure logic (CLI parsing, security, voice, connectors) |
| **McClawProtocol** | WebSocket protocol models (WSRequest, WSResponse, WSEvent) |
| **McClawIPC** | Unix socket IPC with HMAC auth |
| **McClawDiscovery** | Bonjour/network discovery |

---

## 12. Plugin Ecosystem Compatibility

McClaw maintains full compatibility with the plugin ecosystem:

- **Gateway plugins**: managed and run externally on the Gateway; McClaw provides a UI to configure them
- **Skills**: compatible with SKILL.md format and ClawHub
- **Gateway protocol**: same WebSocket protocol (version 3)
- **Configuration**: compatible format with mcclaw.json/toml
- **Channels**: 22+ supported channels (via Gateway)
- **MCP**: support via mcporter
- **Hooks**: compatible hooks system
- **Cron**: same job format and scheduling

The key difference is that McClaw uses the official CLIs as an intermediary instead of direct API keys.
