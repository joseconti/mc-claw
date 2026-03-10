# McClaw - Claude Code Instructions

## Project
Native macOS app (Swift 6.0, SwiftUI, macOS 15+) that wraps official AI CLIs via CLI Bridge. All functionality is native — no external Gateway or server dependencies.

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
- `relay-server/` - Node.js relay for remote mobile access (relay.joseconti.com)
- `docs/McClaw/` - Architecture and design documents
- `SPRINTS.md` - Sprint state and progress tracking

## Conventions
- Actors for concurrent services (CLIBridge, CLIDetector, ConfigStore, RelayClient, MobileServer)
- @Observable + @MainActor for state (AppState, ChatViewModel)
- AsyncStream for CLI streaming
- Config persisted in `~/.mcclaw/mcclaw.json`
- Singletons: `AppState.shared`, `ConfigStore.shared`, `CLIBridge.shared`

## Localization
- **ALL user-facing text MUST be localizable.** Use `String(localized: "key", bundle: .module)` for every visible string in the UI.
- Add all new keys to `McClaw/Sources/McClaw/Resources/en.lproj/Localizable.strings` with `"key" = "value";` format.
- Prompts sent to AI (not shown to user) do NOT need localization — the AI responds in the user's language automatically.
- Never use hardcoded strings for labels, titles, placeholders, error messages, or any text the user sees.

## Goal
McClaw is the native macOS AI assistant that unifies multiple AI providers through their official CLI tools. It provides a rich feature set including chat, voice, canvas, automation, connectors, native channels, device pairing, and skills — all through a single SwiftUI interface.

## Scheduling (Architectural Decision)
- **Claude CLI**: uses BackgroundCLISession with PTY + `/loop` for scheduled tasks
- **Other providers**: uses LocalScheduler for background execution via CLIBridge
- The UI is unified (CronJobEditor), both backends are fully native

## Important
- After each completed sprint, update `SPRINTS.md` marking tasks as done
- Always verify it compiles (`swift build`) and tests pass (`swift test`) before marking as completed
- See `SPRINTS.md` for current sprint progress
