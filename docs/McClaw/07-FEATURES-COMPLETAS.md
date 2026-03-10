# McClaw - Complete Features

## 1. Full Feature Map

McClaw provides all features adapted to a native Mac app, including features specific to the CLI Bridge.

---

## 2. CLI Bridge Features (exclusive to McClaw)

### 2.1 Automatic CLI Detection
- Scanning of installed CLIs at startup and on demand
- Support for: Claude CLI, ChatGPT CLI, Gemini CLI, Ollama, Copilot CLI, Aider
- Extension for user-defined custom CLIs
- Version and authentication status verification

### 2.2 Assisted Installation
- One-click installation from the UI
- Methods: Homebrew, npm, curl, manual
- Visible progress in the interface
- Automatic re-scan after installation

### 2.3 Provider Management
- Default CLI selector
- Configurable fallback order (drag & drop)
- Automatic failover if a CLI fails
- Real-time CLI switching via `/cli` command

### 2.4 Transparent Execution
- Response streaming via stdout
- Tool-use support (if the CLI supports it)
- Response block parsing (text, code, thinking)
- Graceful abort/cancel (SIGINT -> SIGTERM)

---

## 3. Chat Features

### 3.1 Chat Window
- Full chat with markdown rendering
- Syntax highlighting in code blocks
- Inline images
- Tables
- Clickable links
- Auto-scroll to the latest message

### 3.2 Real-Time Streaming
- Partial responses visible as they are generated
- Typing indicator
- Tool usage indicators (tool cards)
- Progress bar for long operations

### 3.3 Sessions
- Main session (main)
- Per-channel sessions (WhatsApp, Telegram, etc.)
- Group sessions
- Cron sessions
- Sub-agents (derived sessions)
- Session selector in the UI
- Persistent session history
- Context compaction (`/compact`)

### 3.4 Chat Commands
| Command | Description |
|---|---|
| `/status` | Session status (model, tokens, cost) |
| `/new` / `/reset` | New clean session |
| `/compact` | Compact context |
| `/think <level>` | Thinking level: off/minimal/low/medium/high/xhigh |
| `/verbose on\|off` | Verbose mode |
| `/usage off\|tokens\|full` | Per-response usage info |
| `/model <name>` | Change model |
| `/cli <name>` | Change active CLI |
| `/restart` | Restart Gateway |
| `/activation mention\|always` | Group activation mode |

### 3.5 Attachments
- File drag & drop
- Images (analysis via vision model)
- PDFs
- Audio files (transcription)
- Video files (analysis)
- Attachment preview before sending

### 3.6 Agent to Agent
- `sessions_list`: discover active agents
- `sessions_history`: view another agent's transcript
- `sessions_send`: send message to another agent (ping-pong)
- `sessions_spawn`: create sub-agent

---

## 4. Voice Features

### 4.1 Voice Wake (Wake-Word)
- Always-on detection of trigger words
- Configurable words (default: "clawd", "claude", "computer")
- Voice recognition via SFSpeechRecognizer
- Configurable chime on trigger detection
- Configurable chime on send
- Configurable silence window (2s flowing, 5s trigger-only)
- Hard stop at 120s to prevent infinite sessions
- 350ms debounce between sessions

### 4.2 Push-to-Talk
- Hotkey: Cmd+Fn (held)
- Immediate capture without wake-word
- Visible overlay while held
- Adopts existing text from wake-word
- Sends on release
- Post-PTT cooldown to prevent re-trigger

### 4.3 Talk Mode (Bidirectional Conversation)
- STT (Speech-to-Text) for input
- TTS (Text-to-Speech) for responses
- ElevenLabs integration + system TTS fallback
- Configurable voice selection
- Silence-based turn-taking (0.7s)
- Continuous conversation mode

### 4.4 Voice Overlay
- Transparent panel with transcribed text
- Committed text (firm) vs. volatile text (partial)
- Audio level indicator
- Cancel and Send buttons
- Keyboard support (Escape = cancel, Enter = send)

### 4.5 Voice Configuration
- Microphone selector (with persistence on disconnect)
- Language selector (primary + additional)
- Live audio level meter
- Trigger word editor
- Test mode (local only, does not send)
- Customizable sounds (trigger and send)

---

## 5. Menu Bar Features

### 5.1 Animated Icon
- Critter with occasional blinking
- Working animation (legs moving)
- Enlarged ears during voice
- Activity badge by type (exec, read, write, edit, attach)
- Paused state (visually disabled)
- Celebration on send (optional)

### 5.2 Context Menu
- Agent status (model, active session)
- Active sessions list with preview
- Usage metrics (tokens, cost)
- Gateway health status
- Quick access: Chat, Canvas, Settings
- Controls: Pause/Resume, Voice Wake, Talk Mode
- Manual health check

### 5.3 Notifications
- System notifications via UNUserNotificationCenter
- Notification overlay (in-app alternative)
- Automatic notification mode selection

---

## 6. Canvas Features

### 6.1 Visual Panel
- WKWebView with custom URL scheme (`mcclaw-canvas://`)
- Borderless, resizable
- Anchored to menu bar or cursor
- Size/position persisted per session
- Auto-reload on file changes

### 6.2 A2UI (Agent-to-UI)
- Declarative UI rendering from the agent
- Components: Text, Column, Row, Button, etc.
- Real-time updates via WebSocket
- A2UI v0.8 support (beginRendering, surfaceUpdate, dataModelUpdate, deleteSurface)

### 6.3 Canvas Capabilities
- Navigation to local and external URLs
- Arbitrary JavaScript execution
- Screenshots (snapshot)
- Custom HTML/CSS/JS content
- Deep links for agent triggering (`mcclaw://agent?...`)

---

## 7. Tool Features

### 7.1 Command Execution (Exec/Bash)
- System command execution
- Interactive mode (PTY)
- Background processes
- Configurable timeout (default 1800s)
- Yield for long commands (default 10000ms)
- Execution approval (deny/allowlist/full/ask)
- Optional sandboxing (Docker)
- Injected environment variables
- Shell detection (bash/sh preferred)

### 7.2 Browser
- Chrome/Chromium control via CDP
- Dedicated profile isolated from personal browser
- Page snapshots (AI snapshot or Role snapshot)
- Navigation, clicks, typing
- JavaScript execution
- File uploads
- SSRF protection
- Multi-profile: managed, system, extension relay

### 7.3 Web Search and Fetch
- `web_search`: Brave, Perplexity, Gemini, Grok, Kimi
- `web_fetch`: HTTP GET + readable content extraction
- 15-minute cache
- Domain/language/region filters
- Protection against private/internal hostnames

### 7.4 Files
- `read`: Read workspace files
- `write`: Write files
- `edit`: Edit with diff (search and replace)
- `apply_patch`: Structured multi-file edits (experimental)
- Option to restrict to workspace (`tools.fs.workspaceOnly`)

### 7.5 Images and PDFs
- Image analysis via vision model
- PDF analysis
- Support for multiple vision providers

### 7.6 Messaging
- Send messages via channels
- Polls (WhatsApp, Teams, Discord)
- Reactions, edits, deletions
- Message pinning
- Threads
- Channel permissions
- Member operations

### 7.7 Nodes
- `system.run`: Execute command on macOS
- `system.notify`: System notification
- `camera.snap/clip/list`: Photo/video capture
- `screen.record`: Screen recording
- `location.get`: Geolocation
- `canvas.*`: Canvas control

### 7.8 Gateway Control
- `gateway.restart`: Restart Gateway
- `gateway.update`: Update Gateway
- `config.get/set/patch/schema`: Configuration management

### 7.9 Loop Detection
- Optional guardrails to detect agent loops
- Detectors: generic repetition, poll without progress, ping-pong
- Configurable thresholds (warning, critical, circuit-breaker)

---

## 8. Channel Features

All channels run on the Gateway (Node.js), not inside the McClaw Swift app. McClaw manages and monitors them via WebSocket RPC.

### 8.1 Core Channels (included in the Gateway)
- WhatsApp (Baileys), Telegram (grammY), Slack (Bolt), Discord (discord.js)
- Google Chat, Signal (signal-cli), BlueBubbles (iMessage), iMessage legacy
- IRC, WebChat

### 8.2 Channels via Plugin (npm install on the Gateway host)
- Microsoft Teams, Matrix, Mattermost, Feishu/Lark, LINE
- Nextcloud Talk, Nostr, Synology Chat, Tlon, Twitch, Zalo

### 8.3 Channel Capabilities
- Simultaneous multi-channel
- Routing by channel/group/user
- DM pairing (security)
- Allowlists
- Typing indicators
- Long message chunking
- Reactions
- Multimedia attachments
- Groups with mention or always-on activation

---

## 9. Automation Features

### 9.1 Cron Jobs
- Three schedule types: at (one-time), every (interval), cron (expression)
- Two execution modes: systemEvent (main session) or agentTurn (isolated)
- Delivery: announce (channel), webhook, none
- Retry with exponential backoff
- Model/thinking override per job
- Lightweight context for fast jobs
- Automatic stagger for top-of-hour jobs
- Execution history (run log)

### 9.2 Webhooks
- External webhook reception
- Result delivery via webhook
- Configurable token auth

### 9.3 Gmail Pub/Sub
- Gmail monitoring via Pub/Sub
- Hooks for processing incoming emails

### 9.4 Heartbeats
- Configurable Gateway polling
- Wake-on-heartbeat for cron jobs

---

## 10. Security Features

### 10.1 Exec Approvals
- Modes: deny, allowlist (ask), full (allow all)
- Persistent allowlist in `~/.mcclaw/exec-approvals.json`
- Visual approval prompt
- Rules by command pattern
- Shell wrapper parsing (detect actual command)
- Environment variable sanitization

### 10.2 Sandbox
- Docker sandbox for non-main sessions
- Tool allowlist per sandbox
- Filesystem restriction to workspace

### 10.3 DM Pairing
- Pairing code for unknown DMs
- Local allowlist per channel
- Configurable policy: pairing or open

### 10.4 TCC (macOS)
- Microphone, Speech Recognition, Notifications
- Accessibility, Screen Recording
- Camera, Location
- Permissions managed from Settings > Permissions

### 10.5 Secure IPC
- Unix sockets with mode 0600
- Peer UID verification
- HMAC challenge/response
- Short TTL to prevent replay

---

## 11. Plugin and Extensibility Features

### 11.1 Plugin Ecosystem Compatibility
- npm plugins from the ecosystem work without modification (they run on the Gateway, not inside McClaw)
- ClawHub skills compatible
- MCP via mcporter
- Compatible system hooks

### 11.2 Plugin Types
- Memory plugins (one active at a time)
- Context engine plugins
- Channel plugins (additional channels)
- Tool plugins (custom tools)
- General plugins

### 11.3 UI Management
- List of installed plugins (fetched from Gateway via WebSocket)
- Enable/disable per plugin
- Installation from npm (executed on the Gateway host, not inside McClaw)
- Link to ClawHub marketplace

---

## 12. Operations Features

### 12.1 Health Monitoring
- Automatic health check every 60s
- Per-channel probes
- Per-channel authentication status
- Session summary
- Manual health check from menu

### 12.2 Logging
- Structured OSLog with categories
- Rolling diagnostics log (JSONL)
- Configurable verbosity
- Privacy-aware logging
- Log viewer in Debug settings

### 12.3 Discovery
- mDNS/Bonjour for local gateways
- Tailscale Serve for LAN
- Wide-area fallback

### 12.4 Updates
- Auto-update via Sparkle (signed builds)
- Channels: stable, beta, dev
- `mcclaw update --channel stable|beta|dev`

### 12.5 Remote Gateway
- SSH tunneling
- Direct connection (Tailscale/HTTPS)
- Remote health checks
- WebChat through the tunnel

---

## 13. UI/UX Features

### 13.1 Onboarding
- First-run wizard
- CLI detection and setup
- Permissions configuration
- Optional channel setup

### 13.2 Settings
- Tabs: About, General, CLIs, Channels, Cron, Sessions, Plugins, Skills, Permissions, Debug
- Reactive configuration (live changes)
- File watcher for external config

### 13.3 Dock
- Configurable dock icon show/hide
- DockIconManager

### 13.4 Shortcuts
- Cmd+Fn: Push-to-talk
- Configurable via system

### 13.5 Deep Links
- `mcclaw://agent?message=...`: agent trigger from Canvas or other apps
- Security confirmation before execution

---

## 14. Workspace Features

### 14.1 Injected Files
- `AGENTS.md`: instructions for the agent
- `SOUL.md`: agent personality
- `TOOLS.md`: tool documentation

### 14.2 Local Skills
- `~/.mcclaw/workspace/skills/<name>/SKILL.md`
- Auto-reload on modification
- Gating by requirements (binaries, env, config)
- Integrated installers (brew, npm, go, uv)

### 14.3 Memory
- Active memory plugin (one at a time)
- `MEMORY.md` + `memory/*.md` in workspace
- Automatic search/indexing
