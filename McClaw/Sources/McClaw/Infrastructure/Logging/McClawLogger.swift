import Logging
import os

/// Configure structured logging for McClaw using swift-log.
/// Sends output to both stdout (for debug) and file (for diagnostics).
enum McClawLogger {
    /// Bootstrap the logging system with multiplexed handlers.
    static func bootstrap() {
        LoggingSystem.bootstrap { label in
            var stdout = StreamLogHandler.standardOutput(label: label)
            stdout.logLevel = .info
            let file = DiagnosticsFileLogHandler(label: label)
            return MultiplexLogHandler([stdout, file])
        }
    }
}
