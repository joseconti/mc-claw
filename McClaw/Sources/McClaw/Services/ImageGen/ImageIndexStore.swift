import Foundation
import Logging

/// Indexes all generated images across sessions for the Multimedia gallery.
/// Scans session JSON files and maintains an in-memory + cached index.
@MainActor
@Observable
final class ImageIndexStore {
    static let shared = ImageIndexStore()

    /// All indexed images sorted by timestamp (newest first).
    private(set) var allImages: [IndexedImage] = []

    private let logger = Logger(label: "ai.mcclaw.imageindex")
    private let fileManager = FileManager.default

    private var sessionsDir: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/sessions", isDirectory: true)
    }

    private var trashDir: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/sessions/trash", isDirectory: true)
    }

    private var cacheFile: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/images/index.json")
    }

    private init() {}

    // MARK: - Index Operations

    /// Rebuild the image index by scanning all session files.
    func refreshIndex() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var indexed: [IndexedImage] = []

        // Scan active sessions
        indexed.append(contentsOf: scanDirectory(sessionsDir, decoder: decoder))

        allImages = indexed.sorted { $0.timestamp > $1.timestamp }
        saveCache()
    }

    /// Load cached index for fast startup, then refresh in background.
    func loadCachedIndex() {
        guard fileManager.fileExists(atPath: cacheFile.path) else {
            refreshIndex()
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: cacheFile)
            allImages = try decoder.decode([IndexedImage].self, from: data)
            logger.info("Loaded cached image index: \(allImages.count) images")
        } catch {
            logger.warning("Failed to load image cache, rebuilding: \(error)")
            refreshIndex()
        }
    }

    /// Images belonging to a specific session.
    func images(forSession sessionId: String) -> [IndexedImage] {
        allImages.filter { $0.sessionId == sessionId }
    }

    /// Check whether a session has any associated image files.
    func hasImages(sessionId: String) -> Bool {
        allImages.contains { $0.sessionId == sessionId }
    }

    /// Delete all image files associated with a session from disk.
    func deleteImageFiles(forSession sessionId: String) {
        let sessionImages = images(forSession: sessionId)
        for img in sessionImages {
            let url = URL(fileURLWithPath: img.filePath)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
                logger.info("Deleted image file: \(img.filePath)")
            }
        }
        // Also check trash sessions for images
        let trashImages = scanDirectoryForSession(trashDir, sessionId: sessionId)
        for path in trashImages {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        refreshIndex()
    }

    /// Get all image file paths for a specific session (from active or trash).
    func imageFilePaths(forSession sessionId: String) -> [String] {
        let fromIndex = images(forSession: sessionId).map(\.filePath)
        if !fromIndex.isEmpty { return fromIndex }
        // Fallback: scan trash
        return scanDirectoryForSession(trashDir, sessionId: sessionId)
    }

    // MARK: - Private Scanning

    private func scanDirectory(_ dir: URL, decoder: JSONDecoder) -> [IndexedImage] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        var result: [IndexedImage] = []

        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(SessionRecord.self, from: data) else {
                continue
            }

            let title = sessionTitle(from: record)

            for message in record.messages {
                for img in message.generatedImages {
                    // Only include images whose files still exist on disk
                    guard fileManager.fileExists(atPath: img.filePath) else { continue }
                    let indexed = IndexedImage(
                        imageId: img.id,
                        sessionId: record.sessionId,
                        sessionTitle: title,
                        filePath: img.filePath,
                        prompt: img.prompt,
                        providerUsed: img.providerUsed,
                        timestamp: img.timestamp
                    )
                    result.append(indexed)
                }
            }
        }
        return result
    }

    private func scanDirectoryForSession(_ dir: URL, sessionId: String) -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let urls = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(SessionRecord.self, from: data),
                  record.sessionId == sessionId else { continue }

            return record.messages.flatMap { $0.generatedImages.map(\.filePath) }
        }
        return []
    }

    private func sessionTitle(from record: SessionRecord) -> String {
        if let firstUser = record.messages.first(where: { $0.role == .user }) {
            let text = firstUser.content.prefix(60)
            return text.count < firstUser.content.count ? "\(text)…" : String(text)
        }
        return String(record.sessionId.prefix(8))
    }

    // MARK: - Cache

    private func saveCache() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let imagesDir = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".mcclaw/images", isDirectory: true)
            try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            let data = try encoder.encode(allImages)
            try data.write(to: cacheFile, options: .atomic)
        } catch {
            logger.warning("Failed to save image cache: \(error)")
        }
    }
}
