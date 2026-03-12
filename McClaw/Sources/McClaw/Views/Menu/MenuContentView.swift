import SwiftUI

/// Compact mini chat content for the floating panel, styled like Claude Desktop.
/// Shows a text input + "New Chat" dropdown + status indicator.
struct MenuContentView: View {
    @Environment(AppState.self) private var appState
    @State private var text: String = ""
    @State private var imageMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            quickActionsRow
        }
        .frame(width: 660)
        .preferredColorScheme(.dark)
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: 12) {
            // McClaw icon
            mcclawPanelIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            MultiLineTextInput(
                text: $text,
                placeholder: imageMode
                    ? "Describe the image you want to create..."
                    : "What can I help you with?",
                font: .systemFont(ofSize: 16),
                minHeight: 36,
                maxHeight: 120,
                onSubmit: sendAndOpen
            )
            .fixedSize(horizontal: false, vertical: true)

            Button(action: sendAndOpen) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color.white.opacity(0.12))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsRow: some View {
        HStack(spacing: 6) {
            Menu {
                Button {
                    startNewChat()
                } label: {
                    Label("New Chat", systemImage: "bubble.left")
                }

                Button {
                    startNewChat()
                } label: {
                    Label("New Code Session", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Divider()

                Button {
                    openMainWindow()
                } label: {
                    Label("Open Chat Window", systemImage: "macwindow")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("New Chat")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                    Image(systemName: "chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
                .liquidGlassCapsule(interactive: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Image generation toggle (only if an image-capable CLI is installed)
            if hasImageCapableCLI {
                Button {
                    imageMode.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: imageMode ? "photo.fill" : "photo")
                            .font(.subheadline)
                            .foregroundStyle(imageMode ? .white : .white.opacity(0.6))
                        Text("Image")
                            .font(.callout)
                            .foregroundStyle(imageMode ? .white : .white.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if imageMode {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.35))
                                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                        } else {
                            Capsule().fill(.white.opacity(0.08))
                        }
                    }
                    .clipShape(Capsule())
                    .liquidGlassCapsule(interactive: false)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // CLI provider selector
            cliSelector
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 2)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasImageCapableCLI: Bool {
        appState.availableCLIs.contains {
            $0.isInstalled && $0.isAuthenticated && $0.capabilities.supportsImageGeneration
        }
    }

    private func sendAndOpen() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newId = UUID().uuidString
        appState.currentSessionId = newId

        if imageMode {
            appState.pendingImagePrompt = trimmed
        } else {
            appState.pendingMessage = trimmed
        }
        text = ""
        imageMode = false

        dismissAndOpenChat()
    }

    private func startNewChat() {
        appState.currentSessionId = UUID().uuidString
        appState.pendingMessage = nil
        text = ""
        dismissAndOpenChat()
    }

    private func openMainWindow() {
        dismissAndOpenChat()
    }

    private func dismissAndOpenChat() {
        appState.dismissMenuBarPanel?()
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        appState.openChatWindowAction?()
    }

    // MARK: - Panel Icon

    private var mcclawPanelIcon: Image {
        let bundle = Bundle.module
        // Direct path access (SPM may not resolve @2x via forResource)
        let url2x = bundle.bundleURL.appendingPathComponent("mcclaw-white@2x.png")
        if FileManager.default.fileExists(atPath: url2x.path),
           let nsImage = NSImage(contentsOf: url2x) {
            return Image(nsImage: nsImage)
        }
        if let url = bundle.url(forResource: "mcclaw-white", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "brain")
    }

    // MARK: - CLI Selector

    @ViewBuilder
    private var cliSelector: some View {
        let installed = appState.installedAIProviders

        if installed.count > 1 {
            // Multiple CLIs: show as dropdown
            Menu {
                ForEach(installed) { cli in
                    Button {
                        appState.currentCLIIdentifier = cli.id
                        Task { await ConfigStore.shared.saveFromState() }
                    } label: {
                        HStack {
                            Text(cli.displayName)
                            if cli.id == appState.currentCLIIdentifier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(appState.currentCLI?.displayName ?? "CLI")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
                .liquidGlassCapsule(interactive: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else if let cli = appState.currentCLI {
            // Single CLI: just show the name
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(cli.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
