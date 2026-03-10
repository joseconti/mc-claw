import Foundation
import Logging

/// Manages the Gateway LaunchAgent for automatic start/stop.
actor LaunchdManager {
    static let shared = LaunchdManager()

    private let logger = Logger(label: "ai.mcclaw.launchd")
    private let agentLabel = "ai.mcclaw.gateway"

    /// Path to the LaunchAgent plist.
    private var plistPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    /// Install the Gateway LaunchAgent.
    func install(gatewayPath: String, port: Int = 3577) async throws {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["node", gatewayPath],
            "EnvironmentVariables": [
                "PORT": "\(port)",
                "NODE_ENV": "production",
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": "/tmp/mcclaw-gateway.log",
            "StandardErrorPath": "/tmp/mcclaw-gateway-error.log",
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistPath)

        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath.path]
        try process.run()
        process.waitUntilExit()

        logger.info("Gateway LaunchAgent installed and loaded")
    }

    /// Uninstall the Gateway LaunchAgent.
    func uninstall() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistPath.path]
        try process.run()
        process.waitUntilExit()

        try FileManager.default.removeItem(at: plistPath)
        logger.info("Gateway LaunchAgent uninstalled")
    }

    /// Check if the Gateway LaunchAgent is running.
    func isRunning() async -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", agentLabel]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
