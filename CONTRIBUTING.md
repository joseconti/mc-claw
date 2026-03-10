# Contributing to McClaw

Thank you for your interest in contributing to McClaw! This guide will help you get started.

## Getting Started

### Prerequisites

- macOS 15 (Sequoia) or later
- Xcode 16+ or Swift 6.0+ toolchain
- At least one AI CLI installed (Claude Code, ChatGPT, Gemini, or Ollama)

### Setup

```bash
git clone https://github.com/joseconti/mc-claw.git
cd mc-claw

# Build and verify
cd McClaw && swift build

# Run tests
cd McClaw && swift test
```

### Building the App

Always use the build script to generate the complete `.app` bundle:

```bash
./scripts/build-app.sh
# Output: build/McClaw.app
```

Do **not** use `swift build` alone for app distribution — it only compiles the binary without the bundle (Info.plist, icon, Sparkle framework, code signing).

## How to Contribute

### Reporting Bugs

1. Check [existing issues](https://github.com/joseconti/mc-claw/issues) to avoid duplicates
2. Open a new issue using the **Bug Report** template
3. Include: macOS version, McClaw version, steps to reproduce, expected vs actual behavior

### Suggesting Features

1. Check [existing issues](https://github.com/joseconti/mc-claw/issues) for similar proposals
2. Open a new issue using the **Feature Request** template
3. Describe the use case and why it would be valuable

### Submitting Code

1. Fork the repository
2. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/my-feature
   ```
3. Make your changes
4. Ensure tests pass:
   ```bash
   cd McClaw && swift test
   ```
5. Ensure the app compiles:
   ```bash
   ./scripts/build-app.sh
   ```
6. Commit with a clear message
7. Push and open a Pull Request

## Code Guidelines

### Architecture

- **Actors** for concurrent services (`CLIBridge`, `CLIDetector`, `ConfigStore`)
- **@Observable + @MainActor** for UI state (`AppState`, view models)
- **AsyncStream** for streaming CLI output
- **Pure logic in McClawKit** — keep it testable, no UI dependencies

### Swift Conventions

- Swift 6.0 strict concurrency
- Use `Sendable` where required
- Prefer value types (structs/enums) over classes
- Use `async/await` instead of callbacks

### Project Structure

| Target | Purpose |
|--------|---------|
| **McClaw** | Main app — views, services, state |
| **McClawKit** | Pure logic — parsing, security, connectors |
| **McClawProtocol** | WebSocket protocol models |
| **McClawIPC** | Unix socket IPC |
| **McClawDiscovery** | Gateway discovery |

### Tests

- All new logic should include tests
- Tests go in `McClaw/Tests/` under the corresponding test target
- Run the full suite before submitting: `cd McClaw && swift test`

## Pull Request Process

1. PRs should target the `main` branch
2. Include a clear description of what changed and why
3. Reference any related issues
4. Ensure all tests pass
5. Keep PRs focused — one feature or fix per PR

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold this code.

## Questions?

- Open a [Discussion](https://github.com/joseconti/mc-claw/discussions) on GitHub
- Visit [mcclaw.app](https://mcclaw.app) for documentation

## License

By contributing, you agree that your contributions will be licensed under the [GPL-3.0 License](LICENSE).
