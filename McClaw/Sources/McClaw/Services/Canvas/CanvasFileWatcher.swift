import Foundation
import Logging

/// Watches a canvas session directory for file changes using DispatchSource.
/// Triggers hot-reload when content files are modified.
@MainActor
final class CanvasFileWatcher {
    private let logger = Logger(label: "ai.mcclaw.canvas.filewatcher")

    /// Callback invoked when files change in the watched directory.
    var onFilesChanged: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var watchedPath: String?

    /// Start watching a directory for changes.
    func watch(directory: URL) {
        stop()

        let path = directory.path
        watchedPath = path

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.error("Cannot open directory for watching: \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.logger.debug("Canvas directory changed: \(path)")
                self?.onFilesChanged?()
            }
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        source.resume()
        self.source = source
        logger.info("Watching canvas directory: \(path)")
    }

    /// Stop watching.
    func stop() {
        source?.cancel()
        source = nil
        watchedPath = nil
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}
