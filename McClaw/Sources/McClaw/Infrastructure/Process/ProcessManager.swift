import Foundation
import Logging

/// Manages child processes (Gateway, CLIs).
actor ProcessManager {
    static let shared = ProcessManager()

    private let logger = Logger(label: "ai.mcclaw.process")
    private var managedProcesses: [String: Process] = [:]

    /// Start a managed process.
    func start(id: String, path: String, arguments: [String] = []) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        managedProcesses[id] = process
        logger.info("Process started: \(id)")
    }

    /// Stop a managed process.
    func stop(id: String) {
        managedProcesses[id]?.terminate()
        managedProcesses.removeValue(forKey: id)
        logger.info("Process stopped: \(id)")
    }

    /// Check if a process is running.
    func isRunning(id: String) -> Bool {
        managedProcesses[id]?.isRunning ?? false
    }
}
