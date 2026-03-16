<p align="center">
  <img src="docs/assets/mcclaw-icon.png" alt="McClaw" width="128" height="128">
</p>

<h1 align="center">McClaw</h1>

<p align="center">
  <strong>The native macOS AI assistant that bridges all your CLI tools in one place.</strong>
</p>

<p align="center">
  <a href="https://mcclaw.app">🌐 mcclaw.app</a>
</p>

<p align="center">
  <a href="https://mcclaw.app">Website</a> •
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#building-from-source">Build</a> •
  <a href="#contributing">Contributing</a> •
  <a href="docs/McClaw/00-INDICE.md">Docs</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015+-blue?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/swift-6.0-orange?logo=swift" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPLv3-blue" alt="License: GPL v3"></a>
  <img src="https://img.shields.io/badge/version-0.10--beta-blue" alt="v0.10-beta">
  <img src="https://img.shields.io/badge/tests-859%20passing-brightgreen" alt="Tests">
</p>

---

## What is McClaw?

McClaw is a **native macOS application** built with Swift and SwiftUI that unifies multiple AI assistants — Claude, ChatGPT, Gemini, and Ollama — through their official CLI tools. Instead of managing API keys or juggling between different apps, McClaw talks directly to the CLIs you already have installed.

One app. All your AIs. Zero API keys.

## Features

### AI Providers
- **Claude** (Anthropic) — Full streaming support, session management, MCP tools, background sessions
- **ChatGPT** (OpenAI) — Chat completions via CLI
- **Gemini** (Google) — Multi-modal conversations
- **Ollama** — Local models, fully offline

### Core
- **CLI Bridge Architecture** — Uses official CLI tools, no API keys, respects provider ToS
- **Unified Chat Interface** — Switch providers mid-conversation, markdown rendering, code highlighting
- **Menu Bar App** — Always accessible, lightweight, stays out of your way
- **Smart CLI Detection** — Auto-discovers installed CLIs, assisted installation for missing ones
- **859 tests** — Comprehensive test suite across 3 SPM targets

### Productivity
- **Canvas Mode** — Live HTML/JS preview panel with hot-reload, bidirectional JS bridge, and file watcher
- **Voice Mode** — Speech-to-text, text-to-speech, push-to-talk, wake word activation
- **Skills System** — Bundled skills for common tasks (PDF, DOCX, PPTX, metrics, competitive analysis, MCP builder)
- **Slash Commands** — Built-in commands for quick actions
- **File Attachments** — Drag & drop or pick files to include in conversations
- **Session Management** — Persistent chat history with export

### Automation & Integration
- **Scheduled Tasks** — Cron jobs and one-off scheduled prompts (Claude via PTY `/loop`, others via LocalScheduler)
- **30+ Connectors** — Google Workspace, GitHub, Slack, Discord, Telegram, Jira, Notion, Trello, Microsoft 365, and more
- **MCP Support** — Model Context Protocol server management (Claude CLI + Gemini settings.json)
- **WordPress MCP Bridge** — 13 sub-connectors with ~278 abilities for WordPress site management
- **Prompt Enrichment** — `@fetch` directive to inject live data from connectors into prompts
- **OAuth + PKCE** — Secure token flows with Keychain storage

### Native Channels
Connect McClaw directly to messaging platforms — no external server needed:
- **Telegram** — Bot API integration
- **Slack** — Workspace bot
- **Discord** — Bot presence
- **Matrix** — Decentralized chat
- **Mattermost** — Team messaging
- **Mastodon** — Fediverse integration
- **Zulip** — Topic-based chat
- **Rocket.Chat** — Self-hosted messaging
- **Twitch** — Live stream chat

### Device Pairing & Remote Access
- **Local Pairing** — QR code pairing with mobile devices via Network.framework WebSocket
- **Relay Server** — Remote access through relay.joseconti.com (JWT auth, WebSocket relay)
- **Self-hosted Mode** — Run your own relay with zero auth requirements

### Node Mode
- **Screen Recording** — ScreenCaptureKit integration for screen context
- **Camera Capture** — AVCapture for visual input
- **Location Services** — CLLocationManager for location-aware prompts
- **Command Dispatch** — Structured command routing for advanced automation

### Security
- **Execution Approvals** — Glob-based allow/deny rules for CLI commands
- **Environment Sanitization** — Strips sensitive env vars before passing to CLIs
- **TCC Compliance** — Proper macOS permission handling (microphone, screen recording, camera, location)
- **Keychain Storage** — OAuth tokens and credentials stored in macOS Keychain
- **IPC Protocol** — Unix socket communication with HMAC authentication

### Advanced
- **Auto-Updates** — Sparkle framework integration
- **Deep Links** — `mcclaw://` URL scheme support
- **Multi-language** — Full localization infrastructure (i18n)
- **Adaptive Learning** — Learns from usage patterns to improve suggestions

## Requirements

- **macOS 15** (Sequoia) or later
- At least one AI CLI installed:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — `npm install -g @anthropic-ai/claude-code`
  - [ChatGPT CLI](https://platform.openai.com) — Check OpenAI docs for installation
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) — `npm install -g @google/gemini-cli`
  - [Ollama](https://ollama.com) — `brew install ollama`

## Installation

### Download

Get the latest release from **[mcclaw.app](https://mcclaw.app)** or from [GitHub Releases](https://github.com/joseconti/mc-claw/releases).

### Homebrew (coming soon)

```bash
brew install --cask mcclaw
```

## Building from Source

### Prerequisites

- Xcode 16+ or Swift 6.0+ toolchain
- macOS 15+

### Build

```bash
# Clone the repository
git clone https://github.com/joseconti/mc-claw.git
cd mc-claw

# Build the full app bundle (recommended)
./scripts/build-app.sh

# The app is generated at build/McClaw.app
open build/McClaw.app
```

### Development

```bash
# Quick compile check
cd McClaw && swift build

# Run tests (859 tests)
cd McClaw && swift test

# Build only the binary (no bundle)
cd McClaw && swift run
```

## Architecture

McClaw is built as a **Swift Package Manager** project with 3 modular targets:

| Target | Description |
|--------|-------------|
| **McClaw** | Main executable — SwiftUI app, views, services, state management |
| **McClawKit** | Core library — CLI parsing, security logic, connectors, voice, canvas, device, channel kits |
| **McClawIPC** | Inter-process communication — Unix socket with HMAC auth |

### Key Design Decisions

- **100% standalone** — No external gateway or server dependencies
- **Actor-based concurrency** — All services use Swift actors for thread safety
- **@Observable pattern** — State management via `@Observable` + `@MainActor`
- **AsyncStream** — Streaming responses from CLIs
- **No API keys required** — Delegates authentication to each CLI's own auth flow

### Dependencies

| Dependency | Purpose |
|-----------|---------|
| [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) | Menu bar window control |
| [swift-log](https://github.com/apple/swift-log) | Structured logging |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Auto-updates |

## Project Structure

```
mc-claw/
├── McClaw/                    # Swift Package
│   ├── Package.swift
│   ├── Sources/
│   │   ├── McClaw/            # Main app target
│   │   │   ├── App/           # Entry point, AppDelegate
│   │   │   ├── State/         # AppState, ViewModels
│   │   │   ├── Views/         # SwiftUI views (Chat, Settings, Voice, Canvas, Security...)
│   │   │   ├── Services/      # CLIBridge, Cron, MCP, Voice, Canvas, Connectors, NativeChannels, Mobile...
│   │   │   ├── Models/        # Data models (CLI, Chat, Connectors, MCP, Skills, Device, Cron...)
│   │   │   └── Infrastructure/ # Config, Logging, Keychain
│   │   ├── McClawKit/         # Core pure-logic library (CLI, Security, Voice, Canvas, Connectors, Device, Channel kits)
│   │   └── McClawIPC/         # Unix socket IPC with HMAC auth
│   └── Tests/                 # 859 tests
├── BundledSkills/             # Built-in skill definitions
├── docs/                      # Architecture documentation
├── scripts/                   # Build and utility scripts
└── SPRINTS.md                 # Development progress tracker
```

## Contributing

We welcome contributions! McClaw is an open-source project and we appreciate help from the community.

Please read our [Contributing Guide](CONTRIBUTING.md) before submitting a pull request.

### Quick Start for Contributors

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes and ensure tests pass: `cd McClaw && swift test`
4. Build the app to verify: `./scripts/build-app.sh`
5. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Documentation

Full architecture documentation is available in the [`docs/McClaw/`](docs/McClaw/) directory:

- [Architecture Overview](docs/McClaw/01-ARQUITECTURA-GENERAL.md)
- [CLI Bridge](docs/McClaw/02-CLI-BRIDGE.md)
- [Chat UI](docs/McClaw/03-UI-CHAT.md)
- [Data Models](docs/McClaw/06-MODELOS-DATOS.md)
- [Features Map](docs/McClaw/07-FEATURES-COMPLETAS.md)
- [Connectors](docs/McClaw/09-CONNECTORS-SPRINTS.md)
- [Scheduling](docs/McClaw/10-SCHEDULES.md)
- [Native Channels](docs/McClaw/11-CHANNELS-NATIVOS.md)
- [Localization](docs/McClaw/13-LOCALIZACION.md)
- [Mobile Apps](docs/McClaw/14-APP-MOVIL.md)
- [Git Integration](docs/McClaw/16-GIT-INTEGRATION.md)
- [Accessibility](docs/McClaw/17-ACCESSIBILITY.md)

## Roadmap

- [ ] Homebrew Cask distribution
- [ ] iOS companion app
- [ ] Android companion app
- [ ] Git integration with AI-powered commit, PR, and branch management
- [ ] Plugin marketplace
- [ ] Tier 1 language translations (28 languages)
- [ ] Themes and appearance customization

## License

McClaw is released under the [GNU General Public License v3.0](LICENSE).

This means:
- **Forks must also be GPLv3** — any derivative work must be released under the same license.
- **Source code must be public** — if you distribute a modified version, you must make the complete source code available to everyone.
- **No proprietary forks** — you cannot take this code and make it closed-source.

## Author

**José Conti** — [mcclaw.app](https://mcclaw.app)

- GitHub: [@joseconti](https://github.com/joseconti)
- X: [@josecontic](https://x.com/josecontic)
- Email: j.conti@joseconti.com

---

<p align="center">
  <a href="https://mcclaw.app">mcclaw.app</a>
</p>
