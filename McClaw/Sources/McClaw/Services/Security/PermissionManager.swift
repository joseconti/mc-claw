import Foundation
import AppKit
import AVFoundation
import UserNotifications
import Logging

/// Manages macOS TCC (Transparency, Consent, and Control) permissions.
/// Checks and requests mic, camera, accessibility, screen recording, and notifications.
@MainActor
@Observable
final class PermissionManager {
    static let shared = PermissionManager()

    var microphoneStatus: PermissionStatus = .unknown
    var cameraStatus: PermissionStatus = .unknown
    var accessibilityStatus: PermissionStatus = .unknown
    var screenRecordingStatus: PermissionStatus = .unknown
    var notificationsStatus: PermissionStatus = .unknown

    private let logger = Logger(label: "ai.mcclaw.permissions")

    // MARK: - Refresh All

    /// Refresh the status of all permissions.
    func refreshAll() {
        checkMicrophone()
        checkCamera()
        checkAccessibility()
        checkScreenRecording()
        Task { await checkNotifications() }
    }

    // MARK: - Microphone

    func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
        logger.info("Microphone permission: \(granted ? "granted" : "denied")")
        return granted
    }

    // MARK: - Camera

    func checkCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = .granted
        case .denied, .restricted:
            cameraStatus = .denied
        case .notDetermined:
            cameraStatus = .notDetermined
        @unknown default:
            cameraStatus = .unknown
        }
    }

    func requestCamera() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = granted ? .granted : .denied
        logger.info("Camera permission: \(granted ? "granted" : "denied")")
        return granted
    }

    // MARK: - Accessibility

    /// Check accessibility permission (cannot request programmatically, must open System Settings).
    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }

    /// Open System Settings to the Accessibility pane.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Screen Recording

    /// Check screen recording permission.
    /// Note: There's no direct API; we use CGWindowListCopyWindowInfo as a proxy.
    func checkScreenRecording() {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        // If we can read window names of other apps, we have permission
        let hasPermission = windowList?.contains(where: { dict in
            guard let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32 else { return false }
            let name = dict[kCGWindowName as String] as? String
            return ownerPID != ProcessInfo.processInfo.processIdentifier && name != nil
        }) ?? false

        screenRecordingStatus = hasPermission ? .granted : .denied
    }

    /// Open System Settings to the Screen Recording pane.
    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Notifications

    func checkNotifications() async {
        guard Bundle.main.bundleIdentifier != nil else {
            notificationsStatus = .unknown
            logger.debug("Skipping notification check — no bundle identifier (running outside .app bundle)")
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            notificationsStatus = .granted
        case .denied:
            notificationsStatus = .denied
        case .notDetermined:
            notificationsStatus = .notDetermined
        @unknown default:
            notificationsStatus = .unknown
        }
    }

    func requestNotifications() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else {
            logger.warning("Cannot request notifications — no bundle identifier (running outside .app bundle)")
            notificationsStatus = .unknown
            return false
        }
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsStatus = granted ? .granted : .denied
            logger.info("Notifications permission: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Notifications permission error: \(error)")
            notificationsStatus = .denied
            return false
        }
    }

    // MARK: - Helper

    /// Open System Settings for a specific permission that can't be requested programmatically.
    func openSystemSettings(for permission: PermissionKind) {
        switch permission {
        case .microphone:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        case .camera:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
        case .accessibility:
            openAccessibilitySettings()
        case .screenRecording:
            openScreenRecordingSettings()
        case .notifications:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Notifications")!)
        }
    }

    private init() {}
}

// MARK: - Types

enum PermissionStatus: String, Sendable {
    case granted
    case denied
    case notDetermined
    case unknown
}

enum PermissionKind: String, CaseIterable, Sendable {
    case microphone
    case camera
    case accessibility
    case screenRecording
    case notifications

    var displayName: String {
        switch self {
        case .microphone: String(localized: "Microphone", bundle: .module)
        case .camera: String(localized: "Camera", bundle: .module)
        case .accessibility: String(localized: "Accessibility", bundle: .module)
        case .screenRecording: String(localized: "Screen Recording", bundle: .module)
        case .notifications: String(localized: "Notifications", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic"
        case .camera: "camera"
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .notifications: "bell"
        }
    }

    var canRequestDirectly: Bool {
        switch self {
        case .microphone, .camera, .notifications: true
        case .accessibility, .screenRecording: false
        }
    }
}
