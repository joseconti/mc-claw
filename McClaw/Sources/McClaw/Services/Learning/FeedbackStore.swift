import Foundation
import Logging

/// Persists raw feedback events to disk for later aggregation by PreferenceEngine.
/// All data stored locally in ~/.mcclaw/learning/feedback/.
actor FeedbackStore {
    static let shared = FeedbackStore()

    private let logger = Logger(label: "ai.mcclaw.learning.feedback")

    private let feedbackDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/learning/feedback", isDirectory: true)
    }()

    /// Maximum age for raw feedback events before purging (30 days).
    private static let maxEventAge: TimeInterval = 30 * 24 * 3600

    private init() {}

    // MARK: - Directory Management

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: feedbackDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Record

    /// Write a single feedback event to disk as a JSON file.
    func record(_ event: FeedbackEvent) throws {
        try ensureDirectory()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let filename = formatter.string(from: event.timestamp)
            .replacingOccurrences(of: ":", with: "-") + ".json"
        let fileURL = feedbackDirectory.appending(component: filename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(event)
        try data.write(to: fileURL, options: .atomic)
        logger.info("Recorded feedback event \(event.id) with \(event.signals.count) signals")
    }

    // MARK: - Query

    /// Read all feedback events recorded since the given date.
    func events(since date: Date) throws -> [FeedbackEvent] {
        try ensureDirectory()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: feedbackDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var events: [FeedbackEvent] = []
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  modDate >= date else {
                continue
            }
            guard let data = try? Data(contentsOf: fileURL),
                  let event = try? decoder.decode(FeedbackEvent.self, from: data) else {
                continue
            }
            events.append(event)
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Count of all stored feedback events.
    func eventCount() -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: feedbackDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return files.filter { $0.pathExtension == "json" }.count
    }

    // MARK: - Cleanup

    /// Purge feedback events older than the given date.
    func purgeOlderThan(_ date: Date) throws {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: feedbackDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var purged = 0
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  modDate < date else {
                continue
            }
            try fm.removeItem(at: fileURL)
            purged += 1
        }
        if purged > 0 {
            logger.info("Purged \(purged) old feedback events")
        }
    }

    /// Purge events older than 30 days.
    func purgeExpired() throws {
        let cutoff = Date().addingTimeInterval(-Self.maxEventAge)
        try purgeOlderThan(cutoff)
    }

    // MARK: - Reset

    /// Delete all feedback data.
    func deleteAll() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: feedbackDirectory.path) {
            try fm.removeItem(at: feedbackDirectory)
        }
        try ensureDirectory()
        logger.info("All feedback data deleted")
    }
}
