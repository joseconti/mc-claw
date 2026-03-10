# McClaw - Claude Code Instructions

## Project
Native macOS app (Swift 6.0, SwiftUI, macOS 15+) that wraps official AI CLIs via CLI Bridge. Connects to Gateway via WebSocket for channels, plugins, and automation.

## Before Working
1. Read `SPRINTS.md` at the project root for current sprint status
2. Read docs in `docs/McClaw/` if you need to understand the architecture (start with `00-INDICE.md`)
3. Compile with `cd McClaw && swift build` to verify state

## Commands
```bash
./scripts/build-app.sh     # Build full app (generates build/McClaw.app with Info.plist, icon, Sparkle, codesign)
cd McClaw && swift build   # Build binary only (no bundle)
cd McClaw && swift test    # Tests
```

**IMPORTANT**: To build the app ALWAYS use `./scripts/build-app.sh`, NOT `swift build` alone. The script generates `build/McClaw.app` with the complete bundle.

## Structure
- `McClaw/` - Swift Package (source code)
- `docs/McClaw/` - Architecture and design documents
- `SPRINTS.md` - Sprint state and progress tracking

## Conventions
- Actors for concurrent services (CLIBridge, CLIDetector, ConfigStore, GatewayConnectionService)
- @Observable + @MainActor for state (AppState, ChatViewModel)
- AsyncStream for CLI streaming
- Config persisted in `~/.mcclaw/mcclaw.json`
- Singletons: `AppState.shared`, `ConfigStore.shared`, `CLIBridge.shared`, `GatewayConnectionService.shared`

## Goal
McClaw is the native macOS AI assistant that unifies multiple AI providers through their official CLI tools. It provides a rich feature set including chat, voice, canvas, automation, connectors, and plugin support — all through a single SwiftUI interface.

## Scheduling (Architectural Decision)
- **Claude CLI**: has native `claude task` → McClaw delegates directly
- **Other providers**: no native scheduling → use Gateway cron via WebSocket
- The UI is unified (CronJobEditor), the backend varies by provider

## Important
- After each completed sprint, update `SPRINTS.md` marking tasks as done
- Always verify it compiles (`swift build`) and tests pass (`swift test`) before marking as completed
- See `SPRINTS.md` for current sprint progress
