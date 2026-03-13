# McClaw - Development Documentation

## Table of Contents

Complete documentation for McClaw, a native macOS application (Swift/SwiftUI) that uses the official AI provider CLIs instead of direct API connections.

---

### Documents

| # | Document | Description |
|---|---|---|
| 01 | [ARQUITECTURA-GENERAL.md](01-ARQUITECTURA-GENERAL.md) | Project vision, high-level architecture, main components, data flows, state management, security model, Swift project directory structure, SPM dependencies |
| 02 | [CLI-BRIDGE.md](02-CLI-BRIDGE.md) | Official CLI execution engine (claude, chatgpt, gemini, ollama), detection/connection screen, assisted installation, CLIProvider protocol, streaming, abort, failover, configuration |
| 03 | [UI-CHAT.md](03-UI-CHAT.md) | Menu bar (animated icon, states, context menu), chat window (SwiftUI), message bubbles, markdown rendering, tool cards, input bar, chat commands, tabbed settings, onboarding wizard, canvas panel, voice overlay |
| 04 | [GATEWAY-PROTOCOL.md](04-GATEWAY-PROTOCOL.md) | WebSocket connection, frame format (request/response/event), all documented RPC methods (40+), push events, Control Channel, local/remote modes, Gateway management via launchd |
| 05 | [CHANNELS-PLUGINS.md](05-CHANNELS-PLUGINS.md) | All supported channels (22+), channel management, routing, DM pairing, plugin system, plugin types, skills, ClawHub, hooks, MCP via mcporter, tools (15+), nodes, automation (cron, webhooks, Gmail) |
| 06 | [MODELOS-DATOS.md](06-MODELOS-DATOS.md) | All Swift data models: ChatMessage, SessionInfo, SessionKey, CLIProviderInfo, GatewayStatus, HealthSnapshot, VoiceWakeConfig, NodeCapability, ExecApprovalRequest, CronJob, PluginInfo, UsageInfo, SkillInfo, and associated types |
| 07 | [FEATURES-COMPLETAS.md](07-FEATURES-COMPLETAS.md) | Exhaustive feature map: CLI Bridge, chat, voice (wake-word, PTT, talk mode), menu bar, canvas, tools, channels, automation, security, plugins, operations, UI/UX, workspace |
| 08 | [PLUGIN-COMPATIBILITY.md](08-PLUGIN-COMPATIBILITY.md) | Plugin ecosystem compatibility: what guarantees compatibility, compatible plugin types, installation, configuration, SDK layer, scenarios, limitations, recommendations, migration |
| 10 | [SCHEDULES.md](10-SCHEDULES.md) | Scheduled actions (Schedules): overview, hybrid architecture (Claude CLI task + Gateway cron), user interface (sidebar + list + detail), AI selector per provider, schedule types (at/every/cron), CRUD flows, Connectors integration |
| 11 | [CHANNELS-NATIVOS.md](11-CHANNELS-NATIVOS.md) | Native Channels planning without Gateway: Telegram (Bot API + long polling), Slack (Socket Mode), Discord (Gateway WebSocket), WhatsApp (future) |
| 12 | [CONNECTOR-WRITE-ACTIONS.md](12-CONNECTOR-WRITE-ACTIONS.md) | Connector write actions: create events, send emails, create tasks, post messages. OAuth scope upgrades, user confirmation flow, security model |
| 13 | [LOCALIZACION.md](13-LOCALIZACION.md) | Multi-language localization: infrastructure, Localizable.strings, SPM integration, language tiers (Tier 1: EU, Tier 2: global, Tier 3: variants) |
| 14 | [APP-MOVIL.md](14-APP-MOVIL.md) | Mobile app study (iPhone and Android) for communicating with McClaw |
| 15 | [BITNET-PROVIDER.md](15-BITNET-PROVIDER.md) | BitNet 1-bit LLM provider (experimental): installation flow, model management, CLI integration, session handling, configuration |
| 16 | [GIT-INTEGRATION.md](16-GIT-INTEGRATION.md) | Git integration: dedicated sidebar section, platform selector (GitHub/GitLab), AI-assisted repo operations (read/write), local git CLI via GitService, chat context enrichment, confirmation flow for write actions |
| 17 | [ACCESSIBILITY.md](17-ACCESSIBILITY.md) | Accesibilidad: VoiceOver labels, Dynamic Type (@ScaledMetric), Reduce Motion, Alto Contraste, Focus Management, convenciones para vistas nuevas |

---

### McClaw Architecture Summary

| Aspect | McClaw |
|---|---|
| **Platform** | Swift/SwiftUI (native macOS) |
| **AI Connection** | Official provider CLI |
| **Authentication** | CLI auth (provider login) |
| **Gateway** | External Gateway (WebSocket, optional) |
| **WS Protocol** | Version 3 |
| **Plugins** | Gateway Plugins (external, run on Gateway) |
| **Channels** | 22+ channels (via Gateway) |
| **Voice** | Native Swift (SFSpeechRecognizer + NSSpeechSynthesizer) |
| **Canvas** | WKWebView |
| **UI** | Pure SwiftUI |
| **TOS** | TOS compliant (uses official CLI) |

---

### Suggested Implementation Order

1. **Phase 1 - Core**: 01-ARQUITECTURA + 02-CLI-BRIDGE
   - Xcode project, Package.swift
   - CLIDetector, CLIBridge, CLIProviders
   - Basic AppState

2. **Phase 2 - Gateway**: 04-GATEWAY-PROTOCOL
   - GatewayConnection (WebSocket)
   - ControlChannel
   - LaunchdManager

3. **Phase 3 - UI**: 03-UI-CHAT
   - Menu bar with icon
   - Basic chat window
   - Settings window

4. **Phase 4 - Features**: 07-FEATURES-COMPLETAS
   - Voice (Voice Wake, PTT)
   - Canvas
   - Onboarding wizard
   - Full settings

5. **Phase 5 - Ecosystem**: 05-CHANNELS + 08-PLUGIN-COMPATIBILITY
   - Channel management from UI
   - Plugin management from UI
   - Skills management

6. **Phase 6 - Polish**: 06-MODELOS + 07-FEATURES
   - All remaining features
   - Health monitoring
   - Logging
   - Auto-updates
