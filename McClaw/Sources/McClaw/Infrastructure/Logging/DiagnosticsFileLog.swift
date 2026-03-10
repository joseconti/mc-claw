import Foundation
import Logging

/// File-based log handler that writes to `~/.mcclaw/logs/mcclaw.log`.
/// Rotates when the file exceeds `maxFileSize`. Keeps one rotated backup.
struct DiagnosticsFileLogHandler: LogHandler {
    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]

    let label: String

    private static let maxFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    private static let queue = DispatchQueue(label: "ai.mcclaw.file-log", qos: .utility)
    // Protected by `queue` serial dispatch — only accessed within queue.async blocks
    nonisolated(unsafe) private static var fileHandle: FileHandle?
    nonisolated(unsafe) private static var currentURL: URL?

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    /// Master switch — set to true to enable file logging.
    nonisolated(unsafe) static var isEnabled: Bool = false

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard Self.isEnabled else { return }

        let merged = self.metadata.merging(metadata ?? [:]) { _, new in new }
        let metaString = merged.isEmpty ? "" : " \(merged)"
        let timestamp = Self.formatter.string(from: Date())
        let entry = "[\(timestamp)] [\(level)] [\(label)] \(message)\(metaString)\n"

        Self.queue.async {
            Self.write(entry)
        }
    }

    // MARK: - File Operations

    static let logsDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let logFileURL: URL = logsDir.appendingPathComponent("mcclaw.log")

    private static func write(_ entry: String) {
        guard let data = entry.data(using: .utf8) else { return }

        if fileHandle == nil {
            openFile()
        }

        // Rotate if needed
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let size = attrs[.size] as? UInt64, size > maxFileSize {
            rotate()
        }

        fileHandle?.write(data)
    }

    private static func openFile() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logFileURL.path) {
            fm.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
        currentURL = logFileURL
    }

    private static func rotate() {
        fileHandle?.closeFile()
        fileHandle = nil

        let rotated = logsDir.appendingPathComponent("mcclaw.log.1")
        let fm = FileManager.default
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: logFileURL, to: rotated)

        openFile()
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Public API

    /// Read the current log file contents (up to last N lines).
    static func readLog(lastLines: Int = 500) -> String {
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8) else {
            return "(no log file)"
        }
        let lines = content.components(separatedBy: "\n")
        let tail = lines.suffix(lastLines)
        return tail.joined(separator: "\n")
    }

    /// Export the log file to a given URL.
    static func exportLog(to destination: URL) throws {
        try FileManager.default.copyItem(at: logFileURL, to: destination)
    }

    /// Clear the log file.
    static func clearLog() {
        Self.queue.async {
            fileHandle?.closeFile()
            fileHandle = nil
            try? FileManager.default.removeItem(at: logFileURL)
            openFile()
        }
    }

    /// Total size of all log files in bytes.
    static var totalLogSize: UInt64 {
        let fm = FileManager.default
        let urls = [logFileURL, logsDir.appendingPathComponent("mcclaw.log.1")]
        var total: UInt64 = 0
        for url in urls {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }
}
