import Foundation
import AppKit
import SwiftUI
import Sparkle
import Logging

/// Manages automatic updates via Sparkle framework.
/// Wraps SPUStandardUpdaterController for SwiftUI integration.
/// Intercepts Sparkle errors to show a custom alert with the McClaw logo.
@MainActor
@Observable
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    /// Whether an update check is in progress
    private(set) var isChecking = false

    /// Whether Sparkle is about to install an update (allows app termination)
    fileprivate(set) var isInstalling = false

    /// Whether an update is available
    private(set) var updateAvailable = false

    /// Whether the user can check for updates (Sparkle readiness)
    private(set) var canCheckForUpdates = false

    /// Last check date
    private(set) var lastCheckDate: Date?

    /// Status message for display
    private(set) var statusMessage: String?

    /// Automatically check for updates on launch
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Update check interval in seconds (default: daily)
    var updateCheckInterval: TimeInterval {
        get { updaterController.updater.updateCheckInterval }
        set { updaterController.updater.updateCheckInterval = newValue }
    }

    private let updaterController: SPUStandardUpdaterController
    private let sparkleDelegate = UpdaterDelegate()
    private let logger = Logger(label: "ai.mcclaw.updater")

    private override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: sparkleDelegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Start the updater. Call once during app launch.
    func start() {
        updaterController.startUpdater()
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        lastCheckDate = updaterController.updater.lastUpdateCheckDate
        logger.info("Sparkle updater started. Auto-check: \(automaticallyChecksForUpdates)")
    }

    /// Manually trigger an update check.
    func checkForUpdates() {
        guard canCheckForUpdates else {
            logger.warning("Cannot check for updates right now")
            return
        }
        isChecking = true
        statusMessage = "Checking for updates…"
        updaterController.checkForUpdates(nil)

        // Sparkle handles the UI flow from here (download, install prompt).
        // Reset state after a delay since Sparkle doesn't have a simple completion callback.
        Task {
            try? await Task.sleep(for: .seconds(5))
            isChecking = false
            lastCheckDate = updaterController.updater.lastUpdateCheckDate
            statusMessage = nil
        }
    }

    /// Current app version string
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Current build number
    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - Sparkle Delegate

/// Intercepts Sparkle updater errors to show a custom McClaw-branded alert
/// with a large centered logo instead of the default small icon.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let logger = Logger(label: "ai.mcclaw.updater.delegate")

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock installationBlock: @escaping () -> Void) {
        // Allow Sparkle to terminate the app even when keepInMenuBar is active
        Task { @MainActor in
            UpdaterService.shared.isInstalling = true
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // Immediate install — allow termination for relaunch
        Task { @MainActor in
            UpdaterService.shared.isInstalling = true
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        // Sparkle fires didAbortWithError for "no update found" (domain SPUNoUpdateFoundError, code 0).
        // This is not a real error — Sparkle already shows its own "You're up to date!" dialog.
        // Only show our custom error alert for actual failures.
        if nsError.domain == "SPUNoUpdateFoundError"
            || error.localizedDescription.contains("up to date") {
            logger.info("No update available — up to date")
            return
        }

        logger.warning("Sparkle error: \(error.localizedDescription)")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = String(localized: "Unable to Check For Updates", bundle: .module)
            alert.informativeText = String(localized: "The updater failed to start. Please verify you have the latest version of McClaw and contact the app developer if the issue still persists.\n\nCheck the Console logs for more information.", bundle: .module)
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "OK", bundle: .module))

            // Large McClaw logo as the alert icon
            if let logoURL = Bundle.module.url(forResource: "mcclaw-logo", withExtension: "png"),
               let logoImage = NSImage(contentsOf: logoURL) {
                logoImage.size = NSSize(width: 128, height: 128)
                alert.icon = logoImage
            }

            alert.runModal()
        }
    }
}
