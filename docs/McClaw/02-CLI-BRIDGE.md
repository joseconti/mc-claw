# McClaw - CLI Bridge Layer

## 1. Concept

The CLI Bridge is McClaw's central component. Instead of connecting directly to AI provider APIs (which violates their TOS in many cases), McClaw acts as a **graphical interface over the official CLIs** of each provider.

```
McClaw App
    |
    v
CLI Bridge Layer
    |
    +---> claude (Anthropic CLI)
    +---> chatgpt (OpenAI CLI)
    +---> gemini (Google CLI)
    +---> ollama (local)
    +---> copilot (GitHub CLI)
    +---> aider (multi-model)
    +---> any compatible CLI
```

---

## 2. Connection Screen (CLI Detection)

McClaw's connection screen **does not ask for API keys**. Instead:

### 2.1 Detection Flow

```
1. On app launch (or when opening Settings > CLIs):
   CLIDetector.scan() executes:

2. For each known CLI:
   - which claude -> /usr/local/bin/claude (or not found)
   - which chatgpt -> ...
   - which gemini -> ...
   - which ollama -> ...
   - etc.

3. For each CLI found:
   - Run `<cli> --version` to get the version
   - Run auth verification command (e.g.: `claude auth status`)
   - Determine if authenticated or needs login

4. Display result in UI:
   +------------------------------------------+
   |  Detected AI CLIs                        |
   |                                          |
   |  [x] Claude CLI v1.2.3                   |
   |      Status: Authenticated               |
   |      Path: /usr/local/bin/claude         |
   |                                          |
   |  [ ] ChatGPT CLI                         |
   |      Status: Not installed               |
   |      [Install with Homebrew]             |
   |                                          |
   |  [x] Ollama v0.5.1                       |
   |      Status: Service active              |
   |      Models: llama3, codestral           |
   |                                          |
   |  [ ] Gemini CLI                          |
   |      Status: Not installed               |
   |      [Install]                           |
   |                                          |
   |  Default CLI: [Claude CLI v]             |
   +------------------------------------------+
```

### 2.2 Assisted Installation

If a CLI is not installed, McClaw offers to install it:

```swift
enum CLIInstallMethod {
    case homebrew(formula: String)     // brew install claude-cli
    case npm(package: String)          // npm install -g @anthropic/claude-cli
    case curl(url: URL)               // curl -fsSL https://... | bash
    case appStore(bundleId: String)    // open macOS App Store
    case manual(instructions: String)  // step-by-step instructions
}
```

The installation process:

```
1. User clicks [Install]
2. McClaw shows confirmation dialog with the command
3. If confirmed:
   - Run the install command via Process()
   - Show progress in the UI
   - On completion, re-scan to verify
4. If the CLI needs authentication:
   - Show instructions: "Run 'claude login' in Terminal"
   - Or open Terminal with the pre-written command
   - Periodic polling to detect when login completes
```

---

## 3. Supported CLI Providers

### 3.1 Claude CLI (Anthropic)

```swift
struct ClaudeCLIProvider: CLIProvider {
    let id = "claude"
    let displayName = "Claude (Anthropic)"
    let binaryName = "claude"

    let installMethods: [CLIInstallMethod] = [
        .npm(package: "@anthropic-ai/claude-code"),
        .homebrew(formula: "claude-code")
    ]

    // Detection
    let versionCommand = ["claude", "--version"]
    let authCheckCommand = ["claude", "auth", "status"]

    // Chat execution
    func buildChatCommand(message: String, options: ChatOptions) -> [String] {
        var args = ["claude", "--message", message]
        if let model = options.model {
            args += ["--model", model]
        }
        if options.thinking != .off {
            args += ["--thinking", options.thinking.rawValue]
        }
        if options.streaming {
            args += ["--stream"]
        }
        return args
    }

    // Response parsing
    func parseOutput(data: Data) -> CLIResponse { ... }

    // Available models
    let defaultModel = "claude-sonnet-4-6"
    let availableModels = [
        "claude-opus-4-6",
        "claude-sonnet-4-6",
        "claude-haiku-4-5"
    ]
}
```

### 3.2 ChatGPT CLI (OpenAI)

```swift
struct ChatGPTCLIProvider: CLIProvider {
    let id = "chatgpt"
    let displayName = "ChatGPT (OpenAI)"
    let binaryName = "chatgpt"

    let installMethods: [CLIInstallMethod] = [
        .homebrew(formula: "chatgpt-cli"),
        .npm(package: "chatgpt-cli")
    ]

    let versionCommand = ["chatgpt", "--version"]
    let authCheckCommand = ["chatgpt", "auth", "verify"]

    func buildChatCommand(message: String, options: ChatOptions) -> [String] {
        var args = ["chatgpt", "chat", "--message", message]
        if let model = options.model {
            args += ["--model", model]
        }
        return args
    }

    let defaultModel = "gpt-4o"
    let availableModels = ["gpt-4o", "gpt-4o-mini", "o1", "o3"]
}
```

### 3.3 Ollama (Local)

```swift
struct OllamaCLIProvider: CLIProvider {
    let id = "ollama"
    let displayName = "Ollama (Local)"
    let binaryName = "ollama"

    let installMethods: [CLIInstallMethod] = [
        .homebrew(formula: "ollama"),
        .curl(url: URL(string: "https://ollama.ai/install.sh")!)
    ]

    let versionCommand = ["ollama", "--version"]
    let authCheckCommand = ["ollama", "list"]  // lists models = it's running

    func buildChatCommand(message: String, options: ChatOptions) -> [String] {
        let model = options.model ?? defaultModel
        return ["ollama", "run", model, message]
    }

    // Ollama: list installed models dynamically
    func listInstalledModels() async -> [String] {
        let output = try await Process.run(["ollama", "list"])
        return parseModelList(output)
    }

    let defaultModel = "llama3"
    var availableModels: [String] {
        get async { await listInstalledModels() }
    }
}
```

### 3.4 Gemini CLI (Google)

```swift
struct GeminiCLIProvider: CLIProvider {
    let id = "gemini"
    let displayName = "Gemini (Google)"
    let binaryName = "gemini"

    let installMethods: [CLIInstallMethod] = [
        .npm(package: "@google/gemini-cli")
    ]

    // ...similar structure
}
```

### 3.5 Generic Provider (Extensible)

```swift
struct GenericCLIProvider: CLIProvider {
    let id: String
    let displayName: String
    let binaryName: String
    let installMethods: [CLIInstallMethod]
    let versionCommand: [String]
    let authCheckCommand: [String]?
    let chatCommandTemplate: String  // "{{binary}} chat --message {{message}}"
    let defaultModel: String?
    let availableModels: [String]

    // Allows the user to define custom CLIs in configuration
}
```

---

## 4. CLIBridge - Execution Engine

### 4.1 Main Interface

```swift
actor CLIBridge {
    static let shared = CLIBridge()

    // State
    private(set) var activeProcess: Process?
    private(set) var isRunning: Bool = false

    // Send a message
    func send(
        message: String,
        provider: CLIProvider,
        options: ChatOptions,
        onPartial: @Sendable (String) -> Void,
        onToolUse: @Sendable (ToolUseEvent) -> Void,
        onComplete: @Sendable (CLIResponse) -> Void
    ) async throws -> CLIResponse

    // Abort current execution
    func abort() async

    // Verify a CLI's status
    func verify(provider: CLIProvider) async -> CLIStatus

    // Install a CLI
    func install(provider: CLIProvider, method: CLIInstallMethod) async throws
}
```

### 4.2 Streaming Execution

```swift
extension CLIBridge {
    func send(
        message: String,
        provider: CLIProvider,
        options: ChatOptions,
        onPartial: @Sendable (String) -> Void,
        onToolUse: @Sendable (ToolUseEvent) -> Void,
        onComplete: @Sendable (CLIResponse) -> Void
    ) async throws -> CLIResponse {

        // 1. Build command
        let command = provider.buildChatCommand(message: message, options: options)

        // 2. Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.environment = buildEnvironment(for: provider)

        // 3. Configure pipes
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // If the CLI supports interactive stdin:
        if provider.supportsInteractiveMode {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
        }

        // 4. Start process
        activeProcess = process
        isRunning = true
        try process.run()

        // 5. Read stdout in streaming mode
        var fullResponse = ""
        let outputHandle = stdoutPipe.fileHandleForReading

        for try await line in outputHandle.bytes.lines {
            // Parse according to CLI format
            let parsed = provider.parseStreamLine(line)

            switch parsed {
            case .text(let chunk):
                fullResponse += chunk
                onPartial(chunk)

            case .toolStart(let event):
                onToolUse(event)

            case .toolResult(let event):
                onToolUse(event)

            case .error(let msg):
                throw CLIBridgeError.cliError(msg)

            case .done:
                break
            }
        }

        // 6. Wait for completion
        process.waitUntilExit()
        isRunning = false
        activeProcess = nil

        // 7. Check exit code
        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CLIBridgeError.exitCode(Int(process.terminationStatus), stderr)
        }

        // 8. Build response
        let response = CLIResponse(
            text: fullResponse,
            provider: provider.id,
            model: options.model ?? provider.defaultModel,
            usage: parseUsage(from: fullResponse)
        )

        onComplete(response)
        return response
    }
}
```

### 4.3 Abort/Cancel

```swift
extension CLIBridge {
    func abort() async {
        guard let process = activeProcess, process.isRunning else { return }

        // Try SIGINT first (graceful)
        process.interrupt()

        // Wait 2 seconds
        try? await Task.sleep(for: .seconds(2))

        // If still running, SIGTERM
        if process.isRunning {
            process.terminate()
        }

        isRunning = false
        activeProcess = nil
    }
}
```

---

## 5. CLIDetector - CLI Detection

```swift
actor CLIDetector {
    static let shared = CLIDetector()

    // Registry of known providers
    private let knownProviders: [CLIProvider] = [
        ClaudeCLIProvider(),
        ChatGPTCLIProvider(),
        OllamaCLIProvider(),
        GeminiCLIProvider(),
        AiderCLIProvider(),
        CopilotCLIProvider()
    ]

    // Scan result
    struct ScanResult {
        let provider: CLIProvider
        let status: CLIStatus
        let path: String?
        let version: String?
        let isAuthenticated: Bool
        let availableModels: [String]
    }

    enum CLIStatus {
        case installed(version: String, authenticated: Bool)
        case installedNotAuth(version: String)
        case notInstalled
        case error(String)
    }

    // Scan all CLIs
    func scan() async -> [ScanResult] {
        await withTaskGroup(of: ScanResult.self) { group in
            for provider in knownProviders {
                group.addTask {
                    await self.checkProvider(provider)
                }
            }
            var results: [ScanResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.provider.displayName < $1.provider.displayName }
        }
    }

    // Check a specific provider
    private func checkProvider(_ provider: CLIProvider) async -> ScanResult {
        // 1. which <binary>
        guard let path = await findBinary(provider.binaryName) else {
            return ScanResult(
                provider: provider,
                status: .notInstalled,
                path: nil,
                version: nil,
                isAuthenticated: false,
                availableModels: []
            )
        }

        // 2. <binary> --version
        let version = await getVersion(provider)

        // 3. auth check (if the provider supports it)
        let isAuth = await checkAuth(provider)

        // 4. list models (if available and authenticated)
        let models = isAuth ? await listModels(provider) : []

        return ScanResult(
            provider: provider,
            status: isAuth
                ? .installed(version: version ?? "unknown", authenticated: true)
                : .installedNotAuth(version: version ?? "unknown"),
            path: path,
            version: version,
            isAuthenticated: isAuth,
            availableModels: models
        )
    }

    private func findBinary(_ name: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

---

## 6. CLIProvider Protocol

```swift
protocol CLIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var binaryName: String { get }
    var installMethods: [CLIInstallMethod] { get }

    // Detection
    var versionCommand: [String] { get }
    var authCheckCommand: [String]? { get }

    // Capabilities
    var supportsStreaming: Bool { get }
    var supportsInteractiveMode: Bool { get }
    var supportsToolUse: Bool { get }
    var supportsVision: Bool { get }
    var supportsThinking: Bool { get }

    // Models
    var defaultModel: String? { get }
    var availableModels: [String] { get }
    func listModels() async -> [ModelInfo]

    // Command building
    func buildChatCommand(message: String, options: ChatOptions) -> [String]
    func buildInteractiveCommand(options: ChatOptions) -> [String]

    // Output parsing
    func parseStreamLine(_ line: String) -> CLIStreamEvent
    func parseOutput(data: Data) -> CLIResponse

    // Environment
    func environmentOverrides() -> [String: String]
}

// Default values
extension CLIProvider {
    var supportsStreaming: Bool { true }
    var supportsInteractiveMode: Bool { false }
    var supportsToolUse: Bool { false }
    var supportsVision: Bool { false }
    var supportsThinking: Bool { false }
    var authCheckCommand: [String]? { nil }

    func environmentOverrides() -> [String: String] { [:] }
}
```

---

## 7. Data Types

```swift
// Chat options
struct ChatOptions: Sendable {
    var model: String?
    var thinking: ThinkingLevel = .off
    var streaming: Bool = true
    var maxTokens: Int?
    var temperature: Double?
    var systemPrompt: String?
    var workingDirectory: String?
    var attachments: [URL]?
}

enum ThinkingLevel: String, Sendable {
    case off, minimal, low, medium, high, xhigh
}

// CLI response
struct CLIResponse: Sendable {
    let text: String
    let provider: String
    let model: String?
    let usage: UsageInfo?
    let toolCalls: [ToolCall]?
    let exitCode: Int
    let duration: TimeInterval
}

// Usage info
struct UsageInfo: Sendable, Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cost: Double?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
}

// Streaming events
enum CLIStreamEvent: Sendable {
    case text(String)
    case toolStart(ToolUseEvent)
    case toolResult(ToolUseEvent)
    case thinking(String)
    case error(String)
    case usage(UsageInfo)
    case done
}

// Tool use event
struct ToolUseEvent: Sendable {
    let name: String
    let phase: ToolPhase    // .start, .result
    let args: [String: Any]?
    let result: String?
    let meta: [String: Any]?
}

enum ToolPhase: String, Sendable {
    case start, result
}

// Errors
enum CLIBridgeError: Error, LocalizedError {
    case cliNotFound(String)
    case cliNotAuthenticated(String)
    case exitCode(Int, String)
    case cliError(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let cli): return "CLI '\(cli)' not found. Install it first."
        case .cliNotAuthenticated(let cli): return "CLI '\(cli)' not authenticated. Run login."
        case .exitCode(let code, let stderr): return "CLI exited with code \(code): \(stderr)"
        case .cliError(let msg): return "CLI error: \(msg)"
        case .timeout: return "Timeout: CLI did not respond in time"
        case .cancelled: return "Execution cancelled by user"
        }
    }
}
```

---

## 8. CLI Bridge Configuration

```json
{
    "cli": {
        "defaultProvider": "claude",
        "providers": {
            "claude": {
                "enabled": true,
                "binaryPath": "/usr/local/bin/claude",
                "defaultModel": "claude-sonnet-4-6",
                "extraArgs": ["--no-analytics"],
                "env": {
                    "CLAUDE_CONFIG_DIR": "~/.claude"
                },
                "timeout": 300
            },
            "ollama": {
                "enabled": true,
                "binaryPath": "/usr/local/bin/ollama",
                "defaultModel": "llama3.2",
                "serverUrl": "http://localhost:11434"
            }
        },
        "fallbackOrder": ["claude", "chatgpt", "ollama"],
        "timeout": 300,
        "maxRetries": 2
    }
}
```

---

## 9. Gateway Integration

The CLI Bridge integrates with the external Gateway (when connected) to:

1. **Handle channel messages**: messages arriving from channels (WhatsApp, Telegram, etc.) are routed to the CLI Bridge
2. **Maintain sessions**: the Gateway manages sessions, context, and channels
3. **Plugin compatibility**: Gateway plugins are unaware that a CLI is used instead of a direct API
4. **Automation**: cron jobs and webhooks can trigger CLI executions via the Gateway

Note: The Gateway is **external and optional**. McClaw can work standalone using just the CLI Bridge for direct chat. The Gateway adds channels, plugins, and automation capabilities.

```
Gateway receives message (from a channel)
    |
    v
McClaw receives event via WebSocket
    |
    v
CLIBridge.send(message, provider, options)
    |
    v
CLI executes and returns response
    |
    v
McClaw sends reply back to Gateway for channel delivery
```

---

## 10. Fallback and Failover

```swift
actor CLIFailoverManager {
    let providers: [CLIProvider]  // ordered by preference

    func sendWithFailover(
        message: String,
        options: ChatOptions
    ) async throws -> CLIResponse {
        var lastError: Error?

        for provider in providers where provider.isAvailable {
            do {
                return try await CLIBridge.shared.send(
                    message: message,
                    provider: provider,
                    options: options,
                    onPartial: { _ in },
                    onToolUse: { _ in },
                    onComplete: { _ in }
                )
            } catch {
                lastError = error
                // Log and continue with next provider
                Logger.cli.warning("Failed \(provider.id), trying next: \(error)")
            }
        }

        throw lastError ?? CLIBridgeError.cliNotFound("No CLI available")
    }
}
```
