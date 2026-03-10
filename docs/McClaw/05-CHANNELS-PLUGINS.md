# McClaw - Channels, Plugins, and Ecosystem

## 1. Messaging Channels

McClaw supports all channels in the ecosystem. Channels run on the Gateway (Node.js), not directly in the Swift app.

### 1.1 Core Channels (included in the Gateway)

| Channel | Technology | Configuration |
|---|---|---|
| **WhatsApp** | Baileys (WebSocket) | QR pairing, `channels.whatsapp.allowFrom` |
| **Telegram** | grammY (Bot API) | `TELEGRAM_BOT_TOKEN` or `channels.telegram.botToken` |
| **Slack** | Bolt SDK | `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN` |
| **Discord** | discord.js | `DISCORD_BOT_TOKEN` or `channels.discord.token` |
| **Google Chat** | Chat API | HTTP Webhook |
| **Signal** | signal-cli | `channels.signal` config |
| **BlueBubbles** | REST API | `channels.bluebubbles.serverUrl` + password |
| **iMessage** | legacy imsg (macOS) | `channels.imessage` (deprecated) |
| **IRC** | IRC protocol | `channels.irc` config |
| **WebChat** | Gateway built-in | Served directly by the Gateway |

### 1.2 Channels via Plugin (npm install on the Gateway host)

| Channel | Package | Notes |
|---|---|---|
| **Microsoft Teams** | `mcclaw-msteams` | Bot Framework, enterprise |
| **Matrix** | `mcclaw-matrix` | Matrix protocol |
| **Mattermost** | `mcclaw-mattermost` | Bot API + WebSocket |
| **Feishu/Lark** | `mcclaw-feishu` | WebSocket bot |
| **LINE** | `mcclaw-line` | Messaging API |
| **Nextcloud Talk** | `mcclaw-nextcloud-talk` | Self-hosted |
| **Nostr** | `mcclaw-nostr` | DMs via NIP-04 |
| **Synology Chat** | `mcclaw-synology-chat` | Webhooks |
| **Tlon** | `mcclaw-tlon` | Urbit-based |
| **Twitch** | `mcclaw-twitch` | IRC chat |
| **Zalo** | `mcclaw-zalo` | Bot API |
| **Zalo Personal** | `mcclaw-zalouser` | QR pairing |

### 1.3 Channel Management from McClaw

```swift
@MainActor
@Observable
class ChannelsStore {
    static let shared = ChannelsStore()

    struct ChannelInfo: Identifiable {
        let id: String              // "whatsapp", "telegram", etc.
        let displayName: String
        let isConfigured: Bool
        let isLinked: Bool
        let authAgeMs: Double?
        let lastProbe: ProbeResult?
        let lastError: String?
    }

    var channels: [ChannelInfo] = []

    // Refresh channel status
    func refresh() async {
        let status: ChannelsStatusResponse = try await GatewayConnection.shared.call(
            method: "channels.status"
        )
        channels = status.channels.map { ChannelInfo(from: $0) }
    }

    // WhatsApp login (QR)
    func loginWhatsApp() async throws {
        // Opens the QR pairing wizard
        try await GatewayConnection.shared.call(method: "channels.login", params: ["channel": "whatsapp"])
    }

    // Logout
    func logout(channel: String) async throws {
        try await GatewayConnection.shared.call(method: "channels.logout", params: ["channel": channel])
    }
}
```

### 1.4 Channel Routing

The Gateway routes incoming messages to sessions according to rules:

```
Incoming message
    |
    v
Channel identifies: sender, group/DM, channel
    |
    v
Routing rules:
    1. DM Policy: "pairing" (pairing code) or "open"
    2. Allowlist: channels.<channel>.allowFrom
    3. Groups: channels.<channel>.groups (group allowlist)
    4. Activation: mention (only when the bot is mentioned) or always
    |
    v
Session key derived:
    agent:<agentId>:<channel>:<accountId>:<senderId|groupId>
    |
    v
Auto-Reply System processes and responds
```

### 1.5 Channel Security (DM Pairing)

By default, direct messages from unknown users are not processed:

```
1. Unknown user sends DM
2. Bot responds with pairing code: "ABCD"
3. Owner runs: mcclaw pairing approve <channel> ABCD
4. Sender is added to the local allowlist
5. Future messages are processed normally
```

---

## 2. Plugin System

### 2.1 Plugin Architecture

Plugins are npm packages that extend Gateway functionality. McClaw is 100% compatible with this ecosystem.

```
npm Plugin
    |
    +-- package.json (with mcclaw metadata)
    +-- src/
    |     +-- index.ts (entry point)
    |     +-- tools/ (custom tools)
    |     +-- hooks/ (event hooks)
    +-- SKILL.md (optional, instructions for the agent)
```

### 2.2 Plugin Runtime

```swift
// Plugins run inside the Gateway (Node.js)
// McClaw manages them via the WebSocket protocol

struct PluginInfo: Identifiable, Codable {
    let id: String
    let name: String
    let version: String
    let enabled: Bool
    let kind: PluginKind?
    let tools: [String]          // exposed tools
    let hooks: [String]          // registered hooks
    let configSchema: AnyCodable? // configuration schema
}

enum PluginKind: String, Codable {
    case memory           // Memory plugin
    case contextEngine    // Alternative context engine
    case channel          // Messaging channel
    case tool             // Additional tools
    case general          // General plugin
}
```

### 2.3 Plugin API (from the plugin's perspective)

Each plugin receives a runtime context with:

```typescript
// Plugin runtime context (TypeScript, runs in the Gateway)
type PluginRuntime = {
    // Configuration
    config: PluginConfig
    workspace: string
    agentDir: string
    sessionDir: string

    // APIs
    subagent: SubagentAPI        // Create sub-agents
    channel: ChannelAPI          // Send messages via channels

    // Message info
    message: {
        channel: string
        sender: string
        sessionKey: string
        isSandboxed: boolean
        isOwner: boolean
    }
}

// Tool factory
type PluginToolFactory = (ctx: PluginToolContext) => AnyAgentTool[]
```

### 2.4 McClaw Plugin Compatibility

McClaw maintains full compatibility because:

1. **Does not modify the Gateway**: plugins run in Node.js inside the Gateway, not in Swift
2. **Same protocol**: McClaw speaks the same WebSocket protocol version 3
3. **Compatible config**: uses the `mcclaw.json` / `mcclaw.toml` format
4. **Tools pass-through**: plugin tools execute in the Gateway
5. **Hooks preserved**: plugin hooks work the same way

```
McClaw (Swift) -> Gateway WS -> Plugin Runtime (Node.js)
                                    |
                                    +-- Plugin tools execute
                                    +-- Plugin hooks fire
                                    +-- Results return via WS
                                    |
McClaw (Swift) <- Gateway WS <------+
```

### 2.5 Installing Plugins from McClaw

```swift
struct PluginsSettingsView: View {
    @State var plugins: [PluginInfo] = []

    var body: some View {
        Form {
            Section("Installed Plugins") {
                ForEach(plugins) { plugin in
                    PluginRow(plugin: plugin)
                }
            }

            Section("Install Plugin") {
                HStack {
                    TextField("npm package name", text: $newPluginName)
                    Button("Install") {
                        installPlugin(newPluginName)
                    }
                }
                Text("Example: mcclaw-plugin-memory-sqlite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Marketplace") {
                Link("Browse plugins on ClawHub",
                     destination: URL(string: "https://clawhub.com/plugins")!)
            }
        }
    }

    func installPlugin(_ name: String) {
        // The Gateway handles installation
        Task {
            try await GatewayConnection.shared.call(
                method: "plugins.install",
                params: ["package": name]
            )
            await refreshPlugins()
        }
    }
}
```

---

## 3. Skills System

### 3.1 What Are Skills

Skills are Markdown-formatted instructions (SKILL.md) that the agent loads for specific tasks. They work as "specialized prompts" with requirement metadata.

### 3.2 Skill Locations

| Type | Path | Precedence |
|---|---|---|
| Workspace | `~/.mcclaw/workspace/skills/<name>/SKILL.md` | High (per agent) |
| Managed | `~/.mcclaw/skills/<name>/SKILL.md` | Medium (shared) |
| Bundled | Included in the McClaw install | Low |

### 3.3 SKILL.md Format

```markdown
---
name: web-scraper
emoji: globe
description: Extract data from web pages
homepage: https://github.com/user/skill
mcclaw:
  requires:
    bins: [node, puppeteer]
    env: [BROWSERLESS_TOKEN]
  install:
    - brew: puppeteer
    - npm: puppeteer
  primaryEnv: BROWSERLESS_TOKEN
---

# Web Scraper Skill

Instructions for the agent on how to perform web scraping...
```

### 3.4 Skill Management from McClaw

```swift
@MainActor
@Observable
class SkillsStore {
    static let shared = SkillsStore()

    struct SkillInfo: Identifiable {
        let id: String
        let name: String
        let description: String?
        let emoji: String?
        let enabled: Bool
        let eligible: Bool           // meets requirements
        let missingRequirements: [String]
        let installers: [Installer]
        let needsApiKey: Bool
    }

    var skills: [SkillInfo] = []

    func refresh() async {
        let status: SkillsStatusResponse = try await GatewayConnection.shared.call(
            method: "skills.status"
        )
        skills = status.skills.map { SkillInfo(from: $0) }
    }

    func install(skill: SkillInfo, installer: Installer) async throws {
        try await GatewayConnection.shared.call(
            method: "skills.install",
            params: ["skillKey": skill.id, "installer": installer.rawValue]
        )
    }

    func updateConfig(skill: SkillInfo, enabled: Bool? = nil, apiKey: String? = nil) async throws {
        var params: [String: Any] = ["skillKey": skill.id]
        if let enabled { params["enabled"] = enabled }
        if let apiKey { params["apiKey"] = apiKey }
        try await GatewayConnection.shared.call(method: "skills.update", params: params)
    }
}
```

### 3.5 ClawHub (Skills Registry)

ClawHub is a public skills registry. McClaw can search, install, and update skills from ClawHub via the Gateway.

---

## 4. Hooks System

### 4.1 What Are Hooks

Hooks are scripts that execute in response to Gateway events (incoming messages, responses, etc.).

### 4.2 Hook Types

| Type | Description |
|---|---|
| **Fire-and-forget** | Executes without waiting for a result |
| **Message transform** | Transforms the message before processing |
| **Gmail watcher** | Monitors Gmail via Pub/Sub |
| **System hook** | Internal system hooks |

### 4.3 Bundled Hooks

| Hook | Description |
|---|---|
| `boot-md` | Injects .md files at session startup |
| `bootstrap-extra-files` | Loads extra files during bootstrap |
| `command-logger` | Logs executed commands |
| `session-memory` | Session memory persistence |

---

## 5. MCP (Model Context Protocol)

### 5.1 Support via mcporter

McClaw supports MCP through `mcporter`:

```
McClaw -> Gateway -> mcporter -> MCP Server
```

Advantages:
- Add/change MCP servers without restarting the Gateway
- Keep the tools/context surface clean
- Reduce the impact of MCP changes on core stability

### 5.2 MCP Configuration

```json
{
    "mcp": {
        "servers": {
            "filesystem": {
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
            },
            "github": {
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-github"],
                "env": {
                    "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_..."
                }
            }
        }
    }
}
```

---

## 6. Tools

### 6.1 Core Tools

| Tool | Description | Runs on |
|---|---|---|
| **exec/bash** | Execute system commands | Gateway host or sandbox |
| **read** | Read files | Gateway host |
| **write** | Write files | Gateway host |
| **edit** | Edit files (diff) | Gateway host |
| **browser** | Chrome/Chromium control via CDP | Gateway host or node |
| **canvas** | Agent-controlled visual panel | macOS node |
| **web_search** | Web search (Brave, Perplexity, Gemini) | Gateway |
| **web_fetch** | HTTP GET + content extraction | Gateway |
| **image** | Image analysis | Via AI provider |
| **pdf** | PDF analysis | Via AI provider |
| **message** | Send/read messages on channels | Gateway |
| **cron** | Scheduled task management | Gateway |
| **sessions** | Inter-session/agent communication | Gateway |
| **agents_list** | List available agents | Gateway |
| **gateway** | Gateway control (restart, config) | Gateway |
| **nodes** | Node control (camera, screen, notify) | Node |

### 6.2 Node Tools (macOS)

When McClaw runs in node mode, it exposes these capabilities to the Gateway:

| Command | Description |
|---|---|
| `system.run` | Execute local command (with approval) |
| `system.notify` | Send system notification |
| `system.which` | Find binary in PATH |
| `canvas.present` | Show Canvas panel |
| `canvas.hide` | Hide Canvas panel |
| `canvas.navigate` | Navigate to URL in Canvas |
| `canvas.evalJS` | Execute JavaScript in Canvas |
| `canvas.snapshot` | Capture Canvas screenshot |
| `canvas.a2ui.push` | Send A2UI to Canvas |
| `canvas.a2ui.reset` | Reset A2UI |
| `camera.list` | List cameras |
| `camera.snap` | Capture photo |
| `camera.clip` | Record short video |
| `screen.record` | Record screen |
| `location.get` | Get location (via IP) |
| `browser.proxy` | Browser command proxy |

---

## 7. Automation (Cron)

### 7.1 Cron Jobs

```swift
struct CronJob: Identifiable, Codable {
    let id: String
    var name: String
    var enabled: Bool
    var schedule: CronSchedule
    var payload: CronPayload
    var delivery: CronDelivery?
    var retryPolicy: RetryPolicy?
}

enum CronSchedule: Codable {
    case at(Date)                    // One-time
    case every(milliseconds: Int)    // Fixed interval
    case cron(expression: String, timezone: String?)  // Cron expression
}

struct CronPayload: Codable {
    let kind: String        // "systemEvent" or "agentTurn"
    let message: String
    let model: String?
    let thinking: String?
    let timeoutSeconds: Int?
    let lightContext: Bool?
    let wakeMode: String?   // "now" or "next-heartbeat"
}

struct CronDelivery: Codable {
    let mode: String        // "announce", "webhook", "none"
    let to: String?         // channel or URL
}
```

### 7.2 Cron UI in McClaw

```swift
struct CronSettingsView: View {
    @State var store: CronJobsStore

    var body: some View {
        Form {
            Section("Active Jobs") {
                ForEach(store.jobs) { job in
                    CronJobRow(job: job)
                }
            }

            Section("Add Job") {
                Button("New Job") {
                    showJobEditor = true
                }
            }

            Section("History") {
                ForEach(store.recentRuns) { run in
                    CronRunRow(run: run)
                }
            }
        }
    }
}
```
