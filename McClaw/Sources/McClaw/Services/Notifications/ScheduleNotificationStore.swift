import Foundation
import UserNotifications
import os

/// Stores schedule execution results as in-app notifications.
/// Also posts macOS native notifications when enabled.
@MainActor @Observable
final class ScheduleNotificationStore {
    static let shared = ScheduleNotificationStore()

    private let logger = Logger(subsystem: "ai.mcclaw", category: "notifications")
    private let storePath: URL
    private let maxEntries = 200

    // MARK: - State

    var entries: [ScheduleNotification] = []
    var unreadCount: Int { entries.filter { !$0.isRead }.count }
    var nativeNotificationsEnabled: Bool = false

    // MARK: - Init

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw", isDirectory: true)
        storePath = dir.appendingPathComponent("notifications.json")
        load()
        checkNativePermission()
    }

    // MARK: - Add

    /// Add a notification from a schedule run result.
    func add(
        scheduleName: String,
        scheduleId: String,
        provider: String?,
        summary: String,
        status: ScheduleNotification.Status
    ) {
        let entry = ScheduleNotification(
            id: UUID().uuidString,
            scheduleName: scheduleName,
            scheduleId: scheduleId,
            provider: provider,
            summary: summary,
            status: status,
            timestamp: Date(),
            isRead: false
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()

        // Post native macOS notification
        if nativeNotificationsEnabled {
            postNativeNotification(entry)
        }
    }

    // MARK: - Read/Delete

    func markAsRead(_ id: String) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].isRead = true
            save()
        }
    }

    func markAllAsRead() {
        for i in entries.indices {
            entries[i].isRead = true
        }
        save()
    }

    func delete(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Native Notifications

    func requestNativePermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            Task { @MainActor in
                self?.nativeNotificationsEnabled = granted
                if let error {
                    self?.logger.error("Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func checkNativePermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let authorized = settings.authorizationStatus == .authorized
            Task { @MainActor in
                ScheduleNotificationStore.shared.nativeNotificationsEnabled = authorized
            }
        }
    }

    private func postNativeNotification(_ entry: ScheduleNotification) {
        let content = UNMutableNotificationContent()
        content.title = entry.scheduleName
        content.body = entry.summary
        content.sound = .default
        content.categoryIdentifier = "SCHEDULE_RESULT"

        let request = UNNotificationRequest(
            identifier: entry.id,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storePath.path) else { return }
        do {
            let data = try Data(contentsOf: storePath)
            entries = try JSONDecoder().decode([ScheduleNotification].self, from: data)
        } catch {
            logger.error("Failed to load notifications: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let dir = storePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storePath, options: .atomic)
        } catch {
            logger.error("Failed to save notifications: \(error.localizedDescription)")
        }
    }
}

// MARK: - Model

struct ScheduleNotification: Identifiable, Codable, Sendable {
    let id: String
    let scheduleName: String
    let scheduleId: String
    let provider: String?
    let summary: String
    let status: Status
    let timestamp: Date
    var isRead: Bool

    enum Status: String, Codable, Sendable {
        case success
        case error
        case timeout
    }
}
