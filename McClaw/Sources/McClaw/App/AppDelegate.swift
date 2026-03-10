import AppKit
import SwiftUI
import Logging
import McClawDiscovery
import Observation

/// Manages app lifecycle events, menu bar status item, and system-level setup.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, @unchecked Sendable {
    private let logger = Logger(label: "ai.mcclaw.app")

    /// Set to true to force-quit even when keepInMenuBar is active (used by menu Quit button).
    var forceQuit = false

    // MARK: - Menu Bar Status Item

    private var statusItem: NSStatusItem?
    private var floatingPanel: FloatingChatPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("McClaw launching...")

        // Activate as foreground app and make window key (needed for swift run)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Menu bar status item — created immediately on main thread
        createStatusItem()

        // Enable fullscreen and fix traffic light buttons for all windows
        for name: Notification.Name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didEnterFullScreenNotification
        ] {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self.configureWindow(window)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            for window in NSApp.windows {
                self.configureWindow(window)
            }
            NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
        }

        Task { @MainActor in
            let appState = AppState.shared
            let configStore = ConfigStore.shared

            // 0. Ensure config directories exist and load saved config
            try? await configStore.ensureDirectories()
            if let config = await configStore.loadConfig() {
                await configStore.applyToState(config)
                logger.info("Config loaded from disk")
            }

            // 0b. Install bundled skills on first launch
            LocalSkillsStore.shared.installBundledSkillsIfNeeded()

            // 1. Scan for installed CLIs
            let detector = CLIDetector()
            let detected = await detector.scan()
            appState.availableCLIs = detected
            print("[DEBUG] AppDelegate: availableCLIs set to \(detected.count) items, installed: \(detected.filter(\.isInstalled).map(\.displayName))")
            print("[DEBUG] AppDelegate: appState identity = \(ObjectIdentifier(appState))")

            // 2. Set default CLI if none saved or saved one not found
            if appState.currentCLI == nil,
               let first = detected.first(where: { $0.isAuthenticated }) {
                appState.currentCLIIdentifier = first.id
            }

            // 3. Always start with a fresh chat session on launch
            appState.currentSessionId = UUID().uuidString

            // 4. Check if first launch -> show onboarding
            if !appState.hasCompletedOnboarding {
                appState.showOnboarding = true
            }

            // 5. Start Gateway connection only if Gateway is reachable
            if appState.hasCompletedOnboarding {
                let discovery = GatewayDiscovery()
                if let endpoint = await discovery.discoverLocal() {
                    logger.info("Gateway found at \(endpoint.host):\(endpoint.port)")
                    await GatewayConnectionService.shared.connect()
                } else {
                    logger.info("No local Gateway detected, skipping connection")
                }
            }

            // 6. Load cached avatar and check for Gravatar updates
            if let email = appState.userEmail, !email.isEmpty {
                // Load cached avatar immediately
                appState.userAvatarImage = GravatarService.shared.cachedImage
                // Check for updates in background
                Task {
                    let updated = await GravatarService.shared.fetchAvatar(for: email)
                    if updated {
                        appState.userAvatarImage = GravatarService.shared.cachedImage
                    }
                }
            }

            // 7. Start Sparkle auto-updater
            UpdaterService.shared.start()

            // 7b. Start local scheduler for background schedule execution
            LocalScheduler.shared.start()

            // 7c. Start native channels (Telegram, etc.)
            NativeChannelsManager.shared.start()

            // 8. Attach floating chat panel to the status item (needs AppState)
            self.attachFloatingPanel()

            // 9. Start observing state for menu bar icon updates
            self.startIconObservation()

            logger.info("McClaw ready. Detected \(detected.count) CLI(s).")
        }
    }

    // MARK: - Status Item Setup

    /// Create the NSStatusItem so it appears in the menu bar.
    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item
        item.isVisible = true // Force visible (SwiftUI App lifecycle defaults to false)

        guard let button = item.button else { return }

        if let img = NSImage(systemSymbolName: "brain", accessibilityDescription: "McClaw") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            button.image = img
            button.imagePosition = .imageOnly
        }
        button.toolTip = "McClaw"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Attach the floating chat panel (requires @MainActor for AppState access).
    @MainActor
    private func attachFloatingPanel() {
        let panelContent = MenuContentView()
            .environment(AppState.shared)

        floatingPanel = FloatingChatPanel(contentView: panelContent)

        AppState.shared.dismissMenuBarPanel = { [weak self] in
            self?.floatingPanel?.dismissPanel()
        }
    }

    // MARK: - Status Item Actions

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusContextMenu()
        } else {
            floatingPanel?.toggle()
        }
    }

    private func showStatusContextMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(title: String(localized: "Open McClaw", bundle: .module), action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "Quit McClaw", bundle: .module), action: #selector(forceQuitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Temporarily set menu so it appears from the status item
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    /// NSMenuDelegate — clear menu after close so left-click works again.
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            AppState.shared.openChatWindowAction?()
        }
    }

    @objc private func forceQuitApp() {
        forceQuit = true
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icon Observation

    /// Reactively update the status item icon when AppState changes.
    @MainActor
    private func startIconObservation() {
        let state = AppState.shared
        withObservationTracking {
            let iconName: String
            if state.isPaused {
                iconName = "pause.circle"
            } else if state.isWorking {
                iconName = "brain.head.profile"
            } else if state.talkModeEnabled {
                iconName = "waveform.circle"
            } else {
                iconName = "brain"
            }
            self.statusItem?.button?.image = NSImage(
                systemSymbolName: iconName,
                accessibilityDescription: "McClaw"
            )
        } onChange: {
            Task { @MainActor [weak self] in
                self?.startIconObservation()
            }
        }
    }

    // MARK: - Window Configuration

    /// Configure window for proper traffic lights and fullscreen support.
    private func configureWindow(_ window: NSWindow) {
        // Skip panels (menu bar popover, floating panel, canvas)
        guard !(window is NSPanel),
              window.title != "",
              window.styleMask.contains(.titled) else { return }

        // Ensure standard style mask bits
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.collectionBehavior.insert(.fullScreenPrimary)

        // Force all standard buttons visible and enabled
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in buttons {
            if let button = window.standardWindowButton(type) {
                button.isHidden = false
                button.isEnabled = true
                button.superview?.isHidden = false
            }
        }

        let isFullScreen = window.styleMask.contains(.fullScreen)
        if isFullScreen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let zoom = window.standardWindowButton(.zoomButton) {
                    zoom.isEnabled = true
                    zoom.isHidden = false
                }
            }
        }
    }

    // MARK: - App Lifecycle

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let state = AppState.shared
        if state.keepInMenuBar && !forceQuit {
            for window in NSApp.windows where window.isVisible {
                window.orderOut(nil)
            }
            NSApp.setActivationPolicy(.accessory)
            logger.info("McClaw hidden to menu bar (keepInMenuBar active)")
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("McClaw shutting down...")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
