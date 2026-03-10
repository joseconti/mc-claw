import Foundation
import Logging

/// Watches file system changes using FSEvents.
/// Used for monitoring config changes, workspace updates, etc.
@MainActor
final class FileWatcher {
    private let logger = Logger(label: "ai.mcclaw.filewatcher")
    private var stream: FSEventStreamRef?

    /// Start watching a directory for changes.
    func watch(path: String, handler: @escaping (String) -> Void) {
        logger.info("Watching: \(path)")
        // TODO: Implement FSEvents stream
    }

    /// Stop watching.
    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
}
