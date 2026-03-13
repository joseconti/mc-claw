import SwiftUI
import Logging

/// McClaw - Native macOS AI Assistant
/// Uses official AI provider CLIs instead of direct API connections.
@main
struct McClawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState.shared
    @State private var themeManager = ThemeManager.shared

    init() {
        // Bootstrap file logging before any Logger instances are created
        McClawLogger.bootstrap()
    }

    var body: some Scene {
        // Main Chat Window (opens automatically on launch)
        Window("McClaw", id: "chat") {
            DeepLinkAwareChat()
                .environment(appState)
                .environment(themeManager)
                .preferredColorScheme(appState.appColorScheme.swiftUIScheme)
        }
        .defaultSize(width: 480, height: 720)
        .defaultPosition(.trailing)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About McClaw") {
                    AboutWindowController.shared.show()
                }
            }
            // Override Cmd+, to open settings inside the main window
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettingsInMainWindow = true
                    appState.openChatWindowAction?()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Canvas Window
        Window("Canvas", id: "canvas") {
            CanvasView()
                .environment(appState)
                .environment(themeManager)
                .preferredColorScheme(appState.appColorScheme.swiftUIScheme)
        }
        .defaultSize(width: 800, height: 600)
    }
}

/// Wrapper that handles deep links and stores the openWindow action for external use.
private struct DeepLinkAwareChat: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ChatWindow()
            .onOpenURL { url in
                DeepLinkRouter.handle(url, openWindow: openWindow)
            }
            .onAppear {
                // Store the openWindow action so AppDelegate/FloatingPanel can open chat
                AppState.shared.openChatWindowAction = { [openWindow] in
                    openWindow(id: "chat")
                }
            }
    }
}
