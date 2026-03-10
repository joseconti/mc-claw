# McClaw - Plugin Ecosystem Compatibility

## 1. Fundamental Principle

McClaw maintains **full compatibility** with the plugin ecosystem. This is possible because plugins do not interact directly with AI providers: they interact with the **Gateway**.

```
Direct API approach:
    Plugin -> Gateway -> Provider API

McClaw:
    Plugin -> Gateway -> CLI Bridge -> Provider's official CLI
```

For the plugin, the experience is identical: it talks to the Gateway, registers tools, hooks, and configuration, and receives/sends messages. The switch from "direct API" to "CLI Bridge" is transparent.

---

## 2. What Ensures Compatibility

### 2.1 Same Gateway
McClaw uses the Gateway (Node.js) without fork or modification. Plugins load into the Gateway process as always.

### 2.2 Same WebSocket Protocol (v3)
McClaw connects to the Gateway with the same WebSocket protocol version 3. All RPC methods, push events, and frame formats are identical.

### 2.3 Same Configuration Structure
McClaw uses the configuration format (`mcclaw.json` / `mcclaw.toml`). Plugins read and write configuration at the same paths and with the same schema.

### 2.4 Same Plugin Runtime
Plugins continue to run in Node.js inside the Gateway process. McClaw does not introduce an alternative plugin runtime.

### 2.5 Same Available APIs
Plugins have access to the same APIs:

```typescript
// These APIs continue to work the same way in McClaw
type PluginRuntime = {
    config: PluginConfig           // Plugin configuration
    workspace: string              // Workspace path
    agentDir: string               // Agent directory
    sessionDir: string             // Session directory

    subagent: SubagentAPI          // Create sub-agents
    channel: ChannelAPI            // Send via channels

    message: {
        channel: string            // Message channel
        sender: string             // Sender
        sessionKey: string         // Session key
        isSandboxed: boolean       // Whether it's sandboxed
        isOwner: boolean           // Whether it's the owner
    }
}
```

---

## 3. Compatible Plugin Types

### 3.1 Tool Plugins

Plugins that register additional tools work without changes. Tools execute in the Gateway, not in the Swift app.

```typescript
// Example: plugin that adds a database tool
export function createTools(ctx: PluginToolContext): AnyAgentTool[] {
    return [{
        name: "database_query",
        description: "Execute SQL query",
        parameters: { query: { type: "string" } },
        execute: async (params) => {
            // Executes in the Gateway (Node.js)
            const result = await db.query(params.query);
            return JSON.stringify(result);
        }
    }];
}
```

**Compatibility**: 100%. Tools run in Node.js inside the Gateway.

### 3.2 Memory Plugins

Memory plugins manage the storage and retrieval of agent memories.

```typescript
// Example: memory plugin with SQLite
export const memoryPlugin: PluginKind = "memory";

export function createMemory(ctx: PluginContext): MemoryAPI {
    return {
        save: async (key, value) => { /* SQLite insert */ },
        recall: async (query) => { /* SQLite search */ },
        forget: async (key) => { /* SQLite delete */ }
    };
}
```

**Compatibility**: 100%. Memory is managed in the Gateway.

### 3.3 Context Engine Plugins

Plugins that provide alternative context engines.

```typescript
export const kind: PluginKind = "context-engine";

export function createContextEngine(ctx: PluginContext): ContextEngine {
    return {
        assemble: async (params) => { /* assemble messages */ },
        compact: async (params) => { /* compact context */ },
        ingest: async (params) => { /* process message */ }
    };
}
```

**Compatibility**: 100%. The context engine runs in the Gateway.

### 3.4 Channel Plugins

Plugins that add new messaging channels.

```typescript
// Example: Microsoft Teams plugin
export function createChannel(ctx: PluginContext): ChannelPlugin {
    return {
        name: "msteams",
        connect: async () => { /* connect to Bot Framework */ },
        send: async (message, target) => { /* send via Teams API */ },
        onMessage: (handler) => { /* register message handler */ }
    };
}
```

**Compatibility**: 100%. Channels are managed in the Gateway.

### 3.5 Hook Plugins

Plugins that register hooks for system events.

```typescript
export function createHooks(ctx: PluginContext) {
    return {
        onMessage: async (message) => { /* before processing */ },
        onReply: async (reply) => { /* before sending response */ },
        onToolCall: async (tool, params) => { /* before executing tool */ }
    };
}
```

**Compatibility**: 100%. Hooks execute in the Gateway.

---

## 4. Plugin Installation

### 4.1 Via npm (standard method, on the Gateway host)

```bash
# From terminal on the Gateway host (not inside McClaw)
npm install -g mcclaw-plugin-xyz

# Or configure in mcclaw.json
{
    "plugins": {
        "entries": {
            "mcclaw-plugin-xyz": {
                "enabled": true,
                "config": { ... }
            }
        }
    }
}
```

### 4.2 Via McClaw UI

```swift
// Settings > Plugins > Install
// McClaw delegates installation to the Gateway via WebSocket RPC
struct PluginInstallView: View {
    @State var packageName: String = ""

    var body: some View {
        HStack {
            TextField("npm package", text: $packageName)
            Button("Install") {
                Task {
                    // The Gateway handles npm install on its host
                    try await GatewayConnection.shared.call(
                        method: "plugins.install",
                        params: ["package": packageName]
                    )
                }
            }
        }
    }
}
```

### 4.3 Via ClawHub

McClaw can browse the ClawHub catalog and install plugins directly:

```swift
struct PluginMarketplaceView: View {
    @State var searchResults: [ClawHubPlugin] = []
    @State var searchQuery: String = ""

    var body: some View {
        VStack {
            TextField("Search plugins...", text: $searchQuery)
                .onSubmit { searchClawHub() }

            List(searchResults) { plugin in
                HStack {
                    VStack(alignment: .leading) {
                        Text(plugin.name).font(.headline)
                        Text(plugin.description).font(.caption)
                    }
                    Spacer()
                    Button("Install") { install(plugin) }
                }
            }
        }
    }
}
```

---

## 5. Plugin Configuration from McClaw

### 5.1 Configuration Schema

Each plugin can define a configuration schema with UI hints:

```typescript
// The plugin defines its schema
export const configSchema = {
    apiKey: {
        type: "string",
        description: "API Key for the service",
        uiHint: "password"  // McClaw displays a password field
    },
    maxResults: {
        type: "number",
        description: "Maximum results to return",
        default: 10,
        uiHint: "slider",
        min: 1,
        max: 100
    },
    enabled: {
        type: "boolean",
        description: "Enable this feature",
        default: true,
        uiHint: "toggle"
    }
};
```

McClaw automatically renders configuration forms based on the schema:

```swift
struct PluginConfigView: View {
    let plugin: PluginInfo
    @State var config: [String: AnyCodable]

    var body: some View {
        Form {
            if let schema = plugin.configSchema {
                ForEach(schema.fields) { field in
                    switch field.uiHint {
                    case "password":
                        SecureField(field.description, text: binding(for: field.key))
                    case "slider":
                        Slider(value: numericBinding(for: field.key),
                               in: Double(field.min!)...Double(field.max!))
                    case "toggle":
                        Toggle(field.description, isOn: boolBinding(for: field.key))
                    default:
                        TextField(field.description, text: binding(for: field.key))
                    }
                }
            }

            Button("Save") { saveConfig() }
        }
    }
}
```

### 5.2 Plugin API Keys

```swift
// Plugin API keys are stored in:
// ~/.mcclaw/mcclaw.json -> skills.entries.<pluginKey>.apiKey
// Or in environment variables

struct PluginApiKeyView: View {
    let plugin: PluginInfo

    var body: some View {
        if plugin.requiresApiKey {
            SecureField("API Key", text: $apiKey)
                .onSubmit {
                    Task {
                        try await GatewayConnection.shared.call(
                            method: "skills.update",
                            params: [
                                "skillKey": plugin.id,
                                "apiKey": apiKey
                            ]
                        )
                    }
                }
        }
    }
}
```

---

## 6. Plugin SDK Compatibility Layer

### 6.1 What McClaw Does Not Modify

| Component | Status |
|---|---|
| Plugin loading mechanism | Unchanged (npm + require) |
| Plugin runtime context | Unchanged |
| Tool registration API | Unchanged |
| Hook registration API | Unchanged |
| Config schema API | Unchanged |
| Channel plugin API | Unchanged |
| Memory plugin API | Unchanged |
| Context engine plugin API | Unchanged |
| Subagent API | Unchanged |
| Channel send API | Unchanged |

### 6.2 What McClaw Adds

| Component | Description |
|---|---|
| CLI Bridge info in context | The plugin can detect that CLI is used instead of direct API |
| Improved management UI | Native macOS settings for plugins |
| Integrated ClawHub browser | Marketplace browsing from the app |

### 6.3 Environment Variable for Detecting McClaw

```bash
# The Gateway sets this variable when McClaw is the client
MCCLAW_CLIENT=1
MCCLAW_VERSION=1.0.0
```

Plugins can use this to adjust behavior if needed (optional, never required).

---

## 7. Compatibility Scenarios

### 7.1 Memory Plugin with Vector Store

```
1. User installs on the Gateway host: npm install -g mcclaw-memory-qdrant
2. Configures in McClaw Settings > Plugins > Qdrant Memory
3. McClaw updates mcclaw.json via Gateway WebSocket RPC
4. Gateway loads the plugin
5. Plugin indexes memory in Qdrant
6. Agent (via CLI) receives context with relevant memories
```

Works transparently.

### 7.2 Channel Plugin (Microsoft Teams)

```
1. User installs on the Gateway host: npm install -g mcclaw-msteams
2. Configures Bot Framework credentials in McClaw Settings (saved to Gateway via WebSocket)
3. Gateway connects to the channel
4. Teams messages arrive at the Gateway
5. Gateway passes to CLI Bridge
6. Response returns to the Teams channel
```

Works the same way. The plugin does not know whether the response came from CLI or API.

### 7.3 Tool Plugin (Database)

```
1. User installs database plugin
2. Agent (via CLI) invokes "database_query" tool
3. Gateway executes the plugin's tool
4. Result returned to the agent via CLI stdout
```

Works the same way.

### 7.4 Plugin That Needs Provider Context

Some plugins might need to know which model/provider is being used. McClaw exposes this information via the Gateway as always, but the provider will be the CLI instead of the direct API. The `provider` field in the context will still contain "anthropic", "openai", etc. according to the active CLI.

---

## 8. Known Limitations

### 8.1 Plugins That Depend on Direct API Key

If a plugin needs an API key from a provider to make independent calls (not through the Gateway), McClaw does not automatically provide that key because it does not have it. The user will need to manually configure the API key in the plugin if necessary.

**Solution**: The plugin can use its own API key configuration (via `configSchema`), independent of McClaw's authentication system.

### 8.2 Plugins That Manipulate the Agent Runtime

If a plugin directly modifies the agent runtime (rare, but possible), it might need adaptation to work with the CLI Bridge.

**Solution**: These plugins are exceptional and can be adapted on a case-by-case basis.

### 8.3 Different Streaming

The CLI Bridge may have slightly different streaming patterns compared to the direct API. Plugins that depend on specific streaming timing might notice differences.

**Solution**: Well-written plugins do not depend on streaming timing. The Gateway protocol normalizes events.

---

## 9. Recommendations for Plugin Developers

1. **Do not assume direct API**: always use the Gateway APIs, never make direct calls to AI providers
2. **Use the config schema**: so McClaw can automatically render configuration UI
3. **Publish on ClawHub**: so McClaw users can easily discover your plugin
4. **Test with CLI Bridge**: verify that your plugin works when the agent uses CLI instead of direct API
5. **MCCLAW_CLIENT variable**: if you need to detect McClaw, use this variable (but avoid it if possible)

---

## 10. Plugin Configuration

Plugins are configured in the `~/.mcclaw/` directory:

1. **Install McClaw**
2. **The Gateway is the same**: already installed plugins continue to work
3. **Configuration**: `~/.mcclaw/mcclaw.json`
4. **Skills**: `~/.mcclaw/workspace/skills/`
5. **Channel credentials**: `~/.mcclaw/credentials/`

```swift
struct McClawPaths {
    static var configDir: URL {
        let mcclaw = home.appendingPathComponent(".mcclaw")

        if FileManager.default.fileExists(atPath: mcclaw.path) {
            return mcclaw
        } else {
            // First install: create .mcclaw
            try? FileManager.default.createDirectory(at: mcclaw, withIntermediateDirectories: true)
            return mcclaw
        }
    }
}
```
