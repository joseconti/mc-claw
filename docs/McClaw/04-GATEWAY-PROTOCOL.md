# McClaw - Gateway Protocol

## 1. Overview

McClaw connects to an **external** Gateway as its optional control plane. The app communicates with the Gateway via WebSocket using protocol version 3. The Gateway is a separate Node.js process (not embedded in McClaw) that manages channels, plugins, cron jobs, and tools.

```
McClaw App (Swift)
    |
    | WebSocket (ws://127.0.0.1:18789)
    |
    v
Gateway (Node.js)
    |
    +-- Channels (WhatsApp, Telegram, Slack, Discord, etc.)
    +-- Plugins (npm ecosystem)
    +-- Cron jobs
    +-- Skills
    +-- Tools (browser, exec, canvas, nodes)
```

---

## 2. WebSocket Connection

### 2.1 GatewayConnection (Swift Actor)

```swift
actor GatewayConnection {
    static let shared = GatewayConnection()

    // Configuration
    struct Config {
        let url: URL          // ws://127.0.0.1:18789
        let token: String?    // authentication token
        let password: String? // alternative password
    }

    // State
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case degraded(String)
    }

    private(set) var state: ConnectionState = .disconnected
    private var webSocket: URLSessionWebSocketTask?
    private var sequence: Int = 0

    // Connect
    func connect(config: Config) async throws {
        state = .connecting
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: config.url)

        // Auth
        if let token = config.token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Protocol
        request.addValue("3", forHTTPHeaderField: "X-Protocol-Version")

        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()

        // Handshake
        try await performHandshake()
        state = .connected

        // Start receive loop
        Task { await receiveLoop() }
    }

    // Disconnect
    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        state = .disconnected
    }
}
```

### 2.2 Frame Format

```swift
// Request frame
struct WSRequest: Codable {
    let type: String = "request"
    let seq: Int
    let method: String
    let params: [String: AnyCodable]?
}

// Response frame
struct WSResponse: Codable {
    let type: String  // "response"
    let seq: Int
    let result: AnyCodable?
    let error: WSError?
}

// Event frame (server push)
struct WSEvent: Codable {
    let type: String  // "event"
    let event: String
    let data: AnyCodable
}

// Error
struct WSError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?
}
```

### 2.3 RPC (Request/Response)

```swift
extension GatewayConnection {
    func call<T: Decodable>(
        method: String,
        params: [String: Any]? = nil
    ) async throws -> T {
        sequence += 1
        let seq = sequence

        let request = WSRequest(
            seq: seq,
            method: method,
            params: params?.mapValues { AnyCodable($0) }
        )

        let data = try JSONEncoder().encode(request)
        try await webSocket?.send(.data(data))

        // Wait for response with matching seq
        return try await waitForResponse(seq: seq)
    }
}
```

---

## 3. Available RPC Methods

### 3.1 Agent

| Method | Description | Params |
|---|---|---|
| `agent` | Send message to agent | `message`, `sessionKey`, `model`, `thinking` |

### 3.2 Status and Health

| Method | Description | Params |
|---|---|---|
| `status` | Overall Gateway status | - |
| `health` | Detailed health check | - |
| `set-heartbeats` | Enable/disable heartbeats | `enabled` |

### 3.3 Configuration

| Method | Description | Params |
|---|---|---|
| `config.get` | Get configuration | `path?` |
| `config.set` | Set config value | `path`, `value` |
| `config.patch` | Partial config patch | `patch` |
| `config.schema` | Configuration schema | `path?` |

### 3.4 Chat

| Method | Description | Params |
|---|---|---|
| `chat.history` | Session history | `sessionKey`, `limit?`, `before?` |
| `chat.send` | Send message via chat | `sessionKey`, `message`, `attachments?` |
| `chat.abort` | Abort active generation | `sessionKey` |
| `chat.inject` | Inject system message | `sessionKey`, `content` |
| `sessions.preview` | Session preview | `sessionKey` |

### 3.5 Sessions

| Method | Description | Params |
|---|---|---|
| `sessions.list` | List active sessions | - |
| `sessions.patch` | Modify session | `sessionKey`, fields... |
| `sessions.spawn` | Create sub-agent | `sessionKey`, `message`, `agentId?` |

### 3.6 Channels

| Method | Description | Params |
|---|---|---|
| `channels.status` | Status of all channels | - |
| `channels.logout` | Disconnect a channel | `channel` |

### 3.7 Models

| Method | Description | Params |
|---|---|---|
| `models.list` | List available models | - |

### 3.8 Skills

| Method | Description | Params |
|---|---|---|
| `skills.status` | Skills status | - |
| `skills.install` | Install a skill | `skillKey`, `installer?` |
| `skills.update` | Update skill config | `skillKey`, `enabled?`, `apiKey?`, `env?` |

### 3.9 Voice Wake

| Method | Description | Params |
|---|---|---|
| `voicewake.get` | Voice wake config | - |
| `voicewake.set` | Update voice wake | `enabled`, `triggers`, etc. |
| `talk.config` | Talk Mode config | - |
| `talk.mode` | Enable/disable Talk | `enabled` |

### 3.10 Nodes

| Method | Description | Params |
|---|---|---|
| `node.list` | List connected nodes | - |
| `node.describe` | Describe node capabilities | `nodeId` |
| `node.invoke` | Execute command on node | `nodeId`, `command`, `params` |
| `node.pair.approve` | Approve node pairing | `pairingCode` |
| `node.pair.reject` | Reject node pairing | `pairingCode` |

### 3.11 Devices

| Method | Description | Params |
|---|---|---|
| `device.pair.list` | List devices | - |
| `device.pair.approve` | Approve device | `deviceId` |
| `device.pair.reject` | Reject device | `deviceId` |

### 3.12 Exec Approvals

| Method | Description | Params |
|---|---|---|
| `exec.approval.resolve` | Resolve exec request | `requestId`, `approved` |

### 3.13 Cron

| Method | Description | Params |
|---|---|---|
| `cron.list` | List jobs | - |
| `cron.add` | Add job | `job` object |
| `cron.remove` | Delete job | `jobId` |
| `cron.update` | Update job | `jobId`, `patch` |
| `cron.status` | Scheduler status | - |
| `cron.runs` | Execution history | `jobId`, `limit?` |
| `cron.run` | Run job now | `jobId` |

### 3.14 Web Auth

| Method | Description | Params |
|---|---|---|
| `web.login.start` | Start web login | - |
| `web.login.wait` | Wait for web login | `loginId` |

### 3.15 Wizard

| Method | Description | Params |
|---|---|---|
| `wizard.start` | Start wizard | - |
| `wizard.next` | Next step | `input?` |
| `wizard.cancel` | Cancel wizard | - |
| `wizard.status` | Wizard status | - |

### 3.16 Gateway

| Method | Description | Params |
|---|---|---|
| `gateway.restart` | Restart Gateway | `delayMs?` |
| `gateway.update` | Update Gateway | - |

---

## 4. Push Events (Server -> Client)

The Gateway sends real-time events via the WebSocket:

### 4.1 Event Types

```swift
enum GatewayEvent: String {
    case presence    // Presence changes (connect/disconnect)
    case health      // Health status
    case channels    // Channel state changes
    case agent       // Agent activity (job start/end, tool use)
    case chat        // Chat messages
    case cron        // Cron job events
    case instance    // Instance events
    case voicewake   // Voice wake events
    case tick        // Heartbeat tick
}
```

### 4.2 Agent Event

```swift
struct AgentEvent: Codable {
    let runId: String           // Execution ID
    let seq: Int                // Sequence number
    let stream: String          // "job" or "tool"
    let ts: Double              // Timestamp
    let data: AgentEventData
    let summary: String?

    // For stream = "job"
    struct JobData: Codable {
        let state: String       // "started", "streaming", "done", "error"
    }

    // For stream = "tool"
    struct ToolData: Codable {
        let phase: String       // "start", "result"
        let name: String        // Tool name
        let meta: [String: AnyCodable]?
        let args: [String: AnyCodable]?
    }
}
```

### 4.3 Chat Event

```swift
struct ChatEvent: Codable {
    let sessionKey: String
    let message: ChatMessage
    let isPartial: Bool?
}
```

### 4.4 Health Event

```swift
struct HealthEvent: Codable {
    let ok: Bool
    let ts: Double
    let channels: [String: ChannelHealth]
    let sessions: SessionsSummary
}

struct ChannelHealth: Codable {
    let configured: Bool?
    let linked: Bool?
    let authAgeMs: Double?
    let probe: ProbeResult?
}
```

### 4.5 Presence Event

```swift
struct PresenceEvent: Codable {
    let entries: [PresenceEntry]
}

struct PresenceEntry: Codable {
    let clientId: String
    let type: String        // "control-ui", "node", "cli", "acp"
    let connectedAt: Double
    let userAgent: String?
}
```

---

## 5. Control Channel (Swift)

```swift
@MainActor
@Observable
class ControlChannel {
    static let shared = ControlChannel()

    var connectionState: ConnectionState = .disconnected
    var lastAgentEvent: AgentEvent?
    var lastHealthEvent: HealthEvent?
    var presenceEntries: [PresenceEntry] = []

    // Event subscription
    private var eventTask: Task<Void, Never>?

    func connect() async {
        connectionState = .connecting

        // Use GatewayConnection's connection
        let gateway = GatewayConnection.shared

        eventTask = Task {
            for await event in gateway.events {
                await handleEvent(event)
            }
        }

        connectionState = .connected
    }

    private func handleEvent(_ event: WSEvent) async {
        switch event.event {
        case "agent":
            if let agentEvent = try? decode(AgentEvent.self, from: event.data) {
                lastAgentEvent = agentEvent
                WorkActivityStore.shared.handleAgentEvent(agentEvent)
            }

        case "health":
            if let healthEvent = try? decode(HealthEvent.self, from: event.data) {
                lastHealthEvent = healthEvent
                HealthStore.shared.update(from: healthEvent)
            }

        case "presence":
            if let presenceEvent = try? decode(PresenceEvent.self, from: event.data) {
                presenceEntries = presenceEvent.entries
            }

        case "chat":
            if let chatEvent = try? decode(ChatEvent.self, from: event.data) {
                NotificationCenter.default.post(
                    name: .chatMessageReceived,
                    object: chatEvent
                )
            }

        case "channels":
            ChannelsStore.shared.handleChannelsEvent(event.data)

        case "cron":
            CronJobsStore.shared.handleCronEvent(event.data)

        default:
            Logger.gateway.debug("Unknown event: \(event.event)")
        }
    }
}
```

---

## 6. Local vs Remote Mode

### 6.1 Local

```
McClaw App -> ws://127.0.0.1:18789 -> Gateway (launchd)
```

- Gateway managed via LaunchAgent (`ai.mcclaw.gateway`)
- The app installs/activates the LaunchAgent
- Quitting the app does NOT stop the Gateway

### 6.2 Remote (SSH)

```
McClaw App -> ws://127.0.0.1:18789 -> SSH Tunnel -> Remote Gateway
```

- SSH tunnel with local port forwarding
- `ssh -L 18789:127.0.0.1:18789 user@remote-host`
- Health checks go through the tunnel

### 6.3 Remote (Direct)

```
McClaw App -> wss://gateway.tailnet.ts.net -> Remote Gateway
```

- Direct connection via Tailscale Serve/Funnel or HTTPS
- Requires auth (token or password)

---

## 7. Local Gateway Management

### 7.1 LaunchAgent Manager

```swift
struct LaunchdManager {
    static let label = "ai.mcclaw.gateway"
    static let plistPath: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }()

    // Install LaunchAgent
    static func install(cliPath: String, port: Int) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [cliPath, "gateway", "--port", "\(port)", "--verbose"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": "/tmp/mcclaw/mcclaw-gateway.log",
            "StandardErrorPath": "/tmp/mcclaw/mcclaw-gateway.log",
            "EnvironmentVariables": [
                "PATH": "/usr/local/bin:/usr/bin:/bin:\(npmGlobalBin)",
                "HOME": NSHomeDirectory()
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistPath)
    }

    // Load
    static func load() throws {
        try shellExec("launchctl", "load", plistPath.path)
    }

    // Unload
    static func unload() throws {
        try shellExec("launchctl", "unload", plistPath.path)
    }

    // Restart
    static func restart() throws {
        let uid = getuid()
        try shellExec("launchctl", "kickstart", "-k", "gui/\(uid)/\(label)")
    }

    // Status
    static func isRunning() -> Bool {
        let uid = getuid()
        let result = try? shellExec("launchctl", "print", "gui/\(uid)/\(label)")
        return result?.contains("state = running") ?? false
    }
}
```

---

## 8. Protocol Compatibility

McClaw uses **exactly the WebSocket protocol version 3**. This means:

1. **The Gateway is client-agnostic** regarding which client connects
2. **Plugins** that communicate via the Gateway work without modification
3. **Tools** (browser, exec, canvas, nodes) work the same way
4. **Messaging channels** work the same way
5. **Skills** from the ecosystem work the same way
6. **Cron jobs** work the same way
7. **Embedded WebChat** works the same way

McClaw uses the **CLI Bridge** to execute the official CLIs instead of calling the APIs directly. This difference is transparent to the Gateway: it receives a response and processes it the same way.
