# McClaw - Data Models

## 1. Chat Models

### 1.1 Chat Message

```swift
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    let sessionKey: String?

    // Metadata
    var isStreaming: Bool = false
    var toolName: String?
    var toolPhase: ToolPhase?
    var usage: UsageInfo?
    var attachments: [Attachment]?
    var provider: String?      // "claude", "chatgpt", etc.
    var model: String?         // "claude-sonnet-4-6", etc.

    // Thinking/reasoning (if the model supports it)
    var thinkingContent: String?
}

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case tool
    case system
}
```

### 1.2 Attachments

```swift
struct Attachment: Identifiable, Codable, Sendable {
    let id: UUID
    let type: AttachmentType
    let url: URL?
    let data: Data?
    let mimeType: String?
    let filename: String?
    let size: Int?
}

enum AttachmentType: String, Codable, Sendable {
    case image
    case audio
    case video
    case document
    case file
}
```

### 1.3 Session

```swift
struct SessionInfo: Identifiable, Codable, Sendable {
    let id: String             // Session UUID
    let key: String            // Canonical session key
    let label: String?         // Human-readable name
    let agentId: String
    let chatType: ChatType
    let messageCount: Int
    let lastActivity: Date?
    let model: String?
    let thinkingLevel: String?

    // Runtime state
    var isActive: Bool = false
    var isProcessing: Bool = false
}

enum ChatType: String, Codable, Sendable {
    case direct       // DM with user
    case group        // Channel group
    case channel      // Channel (IRC, Discord, etc.)
    case cron         // Cron job session
    case subagent     // Sub-agent
    case unknown
}
```

### 1.4 Session Key

The Session Key is the canonical key that identifies a session:

```
Format: agent:<agentId>:<rest>

Examples:
    agent:main:main                           # Main session
    agent:main:whatsapp:+34xxx:+34yyy        # WhatsApp DM
    agent:main:telegram:123456:789012         # Telegram DM
    agent:main:discord:guild123:channel456    # Discord channel
    agent:main:whatsapp:+34xxx:group123      # WhatsApp group
    agent:qa:cron:daily-report:run:abc123    # Cron job
    agent:main:subagent:agent:main:main      # Sub-agent
```

```swift
struct SessionKey: Hashable, Sendable {
    let raw: String
    let agentId: String
    let rest: String
    let chatType: ChatType
    let channel: String?
    let senderId: String?
    let groupId: String?

    static let main = SessionKey(raw: "agent:main:main")

    init(raw: String) {
        self.raw = raw
        // Parse canonical format
        let parts = raw.split(separator: ":")
        self.agentId = parts.count > 1 ? String(parts[1]) : "main"
        self.rest = parts.count > 2 ? parts[2...].joined(separator: ":") : "main"
        // ... derive chatType, channel, senderId, groupId
    }

    var isCronRun: Bool { rest.hasPrefix("cron:") && rest.contains(":run:") }
    var isSubagent: Bool { rest.hasPrefix("subagent:") }
    var isChannelBound: Bool { channel != nil }
}
```

---

## 2. CLI Models

### 2.1 CLI Provider

```swift
struct CLIProviderInfo: Identifiable, Codable, Sendable {
    let id: String                // "claude", "chatgpt", etc.
    let displayName: String
    let binaryName: String
    let binaryPath: String?       // Full path if detected
    let version: String?
    let isInstalled: Bool
    let isAuthenticated: Bool
    let defaultModel: String?
    let availableModels: [ModelInfo]
    let capabilities: CLICapabilities
}

struct CLICapabilities: Codable, Sendable {
    let streaming: Bool
    let interactiveMode: Bool
    let toolUse: Bool
    let vision: Bool
    let thinking: Bool
    let codeExecution: Bool
    let fileAttachments: Bool
}

struct ModelInfo: Identifiable, Codable, Sendable {
    let id: String                // "claude-sonnet-4-6"
    let displayName: String       // "Claude Sonnet 4.6"
    let provider: String          // "anthropic"
    let contextWindow: Int?
    let maxOutputTokens: Int?
    let supportsVision: Bool
    let supportsThinking: Bool
    let pricing: ModelPricing?
}

struct ModelPricing: Codable, Sendable {
    let inputPerMillion: Double?    // USD per million input tokens
    let outputPerMillion: Double?   // USD per million output tokens
    let cacheReadPerMillion: Double?
    let cacheWritePerMillion: Double?
}
```

---

## 3. Gateway Models

### 3.1 Gateway Status

```swift
struct GatewayStatus: Codable {
    let running: Bool
    let version: String?
    let port: Int
    let uptime: TimeInterval?
    let sessions: Int
    let channels: [String: ChannelStatus]
    let health: HealthSnapshot
}

struct ChannelStatus: Codable {
    let configured: Bool
    let linked: Bool
    let authAgeMs: Double?
    let lastError: String?
    let probe: ProbeResult?
}

struct ProbeResult: Codable {
    let ok: Bool?
    let status: Int?
    let error: String?
    let elapsedMs: Double?
}
```

### 3.2 Health Snapshot

```swift
struct HealthSnapshot: Codable {
    let ok: Bool
    let ts: Double
    let durationMs: Double
    let channels: [String: ChannelHealth]
    let heartbeatSeconds: Int?
    let sessions: SessionsSummary
}

struct ChannelHealth: Codable {
    let configured: Bool?
    let linked: Bool?
    let authAgeMs: Double?
    let probe: ProbeResult?
    let lastProbeAt: Double?
}

struct SessionsSummary: Codable {
    let active: Int
    let total: Int
}

enum HealthState: Equatable {
    case unknown
    case ok
    case linkingNeeded
    case degraded(String)
}
```

### 3.3 Presence

```swift
struct PresenceEntry: Codable, Identifiable {
    let clientId: String
    let type: ClientType
    let connectedAt: Date
    let userAgent: String?

    var id: String { clientId }
}

enum ClientType: String, Codable {
    case controlUI = "control-ui"
    case node
    case cli
    case acp
    case mobile
}
```

---

## 4. Configuration Models

### 4.1 Main Configuration

```swift
struct McClawConfig: Codable {
    var agent: AgentConfig?
    var cli: CLIConfig?
    var channels: ChannelsConfig?
    var gateway: GatewayConfig?
    var cron: CronConfig?
    var tools: ToolsConfig?
    var skills: SkillsConfig?
    var plugins: PluginsConfig?
}

struct AgentConfig: Codable {
    var model: String?              // "anthropic/claude-sonnet-4-6"
    var workspace: String?          // "~/.mcclaw/workspace"
    var sandbox: SandboxConfig?
    var imageModel: String?
    var userTimezone: String?
    var timeFormat: String?         // "auto", "12", "24"
}

struct CLIConfig: Codable {
    var defaultProvider: String?    // "claude"
    var providers: [String: CLIProviderConfig]?
    var fallbackOrder: [String]?
    var timeout: Int?               // seconds
    var maxRetries: Int?
}

struct CLIProviderConfig: Codable {
    var enabled: Bool?
    var binaryPath: String?
    var defaultModel: String?
    var extraArgs: [String]?
    var env: [String: String]?
    var timeout: Int?
}

struct GatewayConfig: Codable {
    var port: Int?                  // 18789
    var bind: String?               // "loopback"
    var auth: AuthConfig?
    var tailscale: TailscaleConfig?
    var remote: RemoteConfig?
}

struct SandboxConfig: Codable {
    var mode: String?               // "non-main"
    var browser: BrowserSandboxConfig?
}

struct ToolsConfig: Codable {
    var exec: ExecToolConfig?
    var web: WebToolConfig?
    var browser: BrowserToolConfig?
    var sessions: SessionsToolConfig?
    var loopDetection: LoopDetectionConfig?
}
```

### 4.2 Configuration Paths

```swift
struct McClawPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".mcclaw")

    static let config = home.appendingPathComponent("mcclaw.json")
    static let configToml = home.appendingPathComponent("mcclaw.toml")
    static let credentials = home.appendingPathComponent("credentials")
    static let sessions = home.appendingPathComponent("sessions")
    static let workspace = home.appendingPathComponent("workspace")
    static let skills = home.appendingPathComponent("skills")
    static let plugins = home.appendingPathComponent("plugins")
    static let cron = home.appendingPathComponent("cron")
    static let logs = home.appendingPathComponent("logs")

    // Canvas
    static let canvas = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("McClaw/canvas")

    // Workspace files
    static let agentsMd = workspace.appendingPathComponent("AGENTS.md")
    static let soulMd = workspace.appendingPathComponent("SOUL.md")
    static let toolsMd = workspace.appendingPathComponent("TOOLS.md")
}
```

---

## 5. Voice Models

### 5.1 Voice Wake

```swift
struct VoiceWakeConfig: Codable, Sendable {
    var enabled: Bool
    var triggerWords: [String]      // ["clawd", "claude", "computer"]
    var locale: String?             // "en_US"
    var additionalLocales: [String]?
    var microphoneId: String?
    var microphoneName: String?
    var triggerChime: VoiceWakeChime?
    var sendChime: VoiceWakeChime?
}

enum VoiceWakeChime: Codable, Sendable {
    case system(name: String)       // System sound (e.g., "Glass")
    case custom(path: String)       // Audio file
    case none                       // No sound
}

struct VoiceSession: Identifiable, Sendable {
    let id: UUID
    let token: UUID
    let source: VoiceSource
    var committedText: String
    var volatileText: String
    var state: VoiceSessionState
    let startTime: Date
}

enum VoiceSource: Sendable {
    case wakeWord
    case pushToTalk
}

enum VoiceSessionState: Sendable {
    case capturing
    case finalizing
    case sending
    case dismissed
}
```

### 5.2 Talk Mode

```swift
struct TalkModeConfig: Codable, Sendable {
    var enabled: Bool
    var voice: String?              // Selected TTS voice
    var model: String?              // Model for TTS
    var silenceWindow: TimeInterval  // 0.7s by default
    var autoSend: Bool              // Automatically send when silence is detected
}
```

---

## 6. Node Models

### 6.1 Node Capabilities

```swift
enum NodeCapability: String, Codable, Sendable {
    case appleScript
    case notifications
    case accessibility
    case screenRecording
    case microphone
    case speechRecognition
    case camera
    case location
    case canvas
    case browserProxy
    case systemRun
}

struct NodeInfo: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let platform: String            // "macos", "ios", "android"
    let capabilities: [NodeCapability]
    let permissions: [String: Bool]  // capability -> granted
    let isConnected: Bool
    let connectedAt: Date?
}
```

### 6.2 Canvas

```swift
enum CanvasPlacement: Codable, Sendable {
    case menuBar                    // Anchored to the menu bar
    case cursor                     // Near the cursor
    case custom(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)
}

enum CanvasShowStatus: String, Codable, Sendable {
    case shown                      // Panel visible, no navigation
    case web                        // HTTP(S) or file:// URL
    case ok                         // Local file found
    case notFound                   // 404
    case welcome                    // Default scaffold
}

struct CanvasShowResult: Codable, Sendable {
    let status: CanvasShowStatus
    let url: String?
    let error: String?
}
```

---

## 7. Exec/Security Models

### 7.1 Exec Approvals

```swift
enum ExecSecurityMode: String, Codable, Sendable {
    case deny                       // Block everything
    case allowlist                  // Ask for approval per command
    case full                       // Allow everything
}

struct ExecApprovalRequest: Identifiable, Codable, Sendable {
    let id: UUID
    let command: String
    let workingDirectory: String?
    let sessionKey: String
    let timestamp: Date
    let needsElevated: Bool
}

struct ExecApprovalRule: Codable, Sendable {
    let pattern: String             // Command glob pattern
    let allowed: Bool
    let createdAt: Date
}
```

---

## 8. Cron Models

```swift
struct CronJob: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var enabled: Bool
    var schedule: CronScheduleType
    var payload: CronPayload
    var delivery: CronDelivery?
    var retryPolicy: CronRetryPolicy?
    var lastRun: CronRunInfo?
    var nextRunAt: Date?
}

enum CronScheduleType: Codable, Sendable {
    case at(Date)
    case every(milliseconds: Int)
    case cron(expression: String, timezone: String?)
}

struct CronPayload: Codable, Sendable {
    let kind: CronPayloadKind
    let message: String
    let model: String?
    let thinking: String?
    let timeoutSeconds: Int?
    let lightContext: Bool?
    let wakeMode: CronWakeMode?
}

enum CronPayloadKind: String, Codable, Sendable {
    case systemEvent
    case agentTurn
}

enum CronWakeMode: String, Codable, Sendable {
    case now
    case nextHeartbeat = "next-heartbeat"
}

struct CronRunInfo: Codable, Sendable {
    let runId: String
    let jobId: String
    let startedAt: Date
    let finishedAt: Date?
    let status: CronRunStatus
    let summary: String?
    let error: String?
    let durationMs: Double?
}

enum CronRunStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

struct CronDelivery: Codable, Sendable {
    let mode: String            // "announce", "webhook", "none"
    let to: String?
}

struct CronRetryPolicy: Codable, Sendable {
    let maxAttempts: Int?
    let backoffMs: Int?
    let retryOn: [String]?      // "transient", "permanent"
}
```

---

## 9. Plugin Models

```swift
struct PluginInfo: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let enabled: Bool
    let kind: PluginKind?
    let tools: [String]
    let hooks: [String]
    let homepage: String?
    let author: String?
}

enum PluginKind: String, Codable, Sendable {
    case memory
    case contextEngine = "context-engine"
    case channel
    case tool
    case general
}
```

---

## 10. Usage/Metrics Models

```swift
struct UsageInfo: Codable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cost: Double?           // USD
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let latencyMs: Double?
    let model: String?
    let provider: String?
}

struct SessionUsageAggregate: Codable, Sendable {
    let sessionKey: String
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCost: Double
    let messageCount: Int
    let byModel: [String: UsageInfo]
    let byDay: [String: UsageInfo]
}
```

---

## 11. Skill Models

```swift
struct SkillInfo: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let description: String?
    let emoji: String?
    let homepage: String?
    let location: SkillLocation
    let enabled: Bool
    let eligible: Bool
    let missingRequirements: [Requirement]
    let installers: [SkillInstaller]
    let primaryEnv: String?
    let requiresApiKey: Bool
}

enum SkillLocation: String, Codable, Sendable {
    case bundled
    case managed
    case workspace
}

struct Requirement: Codable, Sendable {
    let type: String            // "bin", "env", "config"
    let name: String
    let satisfied: Bool
}

enum SkillInstaller: String, Codable, Sendable {
    case brew
    case npm
    case go
    case uv
    case pip
}
```
