import Foundation
import McClawKit

/// Sanitizes environment variables before passing them to CLI processes.
/// Delegates to SecurityKit for the actual filtering logic.
enum HostEnvSanitizer {

    /// Sanitize environment variables for a command execution.
    static func sanitize(
        env: [String: String] = ProcessInfo.processInfo.environment,
        overrides: [String: String]? = nil,
        isShellWrapper: Bool = false
    ) -> [String: String] {
        SecurityKit.sanitizeEnvironment(
            env: env,
            overrides: overrides,
            isShellWrapper: isShellWrapper
        )
    }
}
