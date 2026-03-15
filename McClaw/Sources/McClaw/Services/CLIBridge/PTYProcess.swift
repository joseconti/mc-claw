import Darwin
import Foundation
import Logging

/// Errors thrown by PTYProcess operations.
enum PTYError: Error, LocalizedError {
    case forkFailed(Int32)
    case writeFailed(Int32)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .forkFailed(let errno): return "forkpty() failed with errno \(errno)"
        case .writeFailed(let errno): return "write() failed with errno \(errno)"
        case .notRunning: return "PTY process is not running"
        }
    }
}

/// Encapsulates POSIX pseudo-terminal operations for launching a child process
/// with a real TTY. This makes the child believe it has an interactive terminal,
/// enabling features like slash commands in Claude CLI.
///
/// Uses `nonisolated(unsafe)` for mutable state, matching the pattern used by
/// `LineBuffer` and `TaskOutputState` in `BackgroundCLISession`.
final class PTYProcess: Sendable {

    private let logger = Logger(label: "ai.mcclaw.pty-process")
    private let ptyQueue = DispatchQueue(label: "ai.mcclaw.pty-read", qos: .userInitiated)

    nonisolated(unsafe) var masterFD: Int32 = -1
    nonisolated(unsafe) var childPID: pid_t = -1
    nonisolated(unsafe) var isRunning: Bool = false
    nonisolated(unsafe) private var readSource: DispatchSourceRead?

    // MARK: - Launch

    /// Launch a child process inside a pseudo-terminal.
    ///
    /// After this call, `masterFD` is a file descriptor for reading stdout
    /// and writing stdin of the child process. The child sees a real TTY.
    ///
    /// - Parameters:
    ///   - executablePath: Full path to the binary (e.g. `/usr/local/bin/claude`)
    ///   - arguments: CLI arguments (without the binary name — it's prepended automatically)
    ///   - environment: Environment variables for the child process
    func launch(
        executablePath: String,
        arguments: [String],
        environment: [String: String]
    ) throws {
        var master: Int32 = -1

        // Prepare argv: [binary, arg1, arg2, ..., NULL]
        var allArgs = [executablePath] + arguments
        let cArgs: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) } + [nil]

        // Prepare envp: ["KEY=VALUE", ..., NULL]
        let cEnv: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]

        let pid = forkpty(&master, nil, nil, nil)

        if pid < 0 {
            // Free allocated strings
            cArgs.forEach { $0.map { free($0) } }
            cEnv.forEach { $0.map { free($0) } }
            throw PTYError.forkFailed(Darwin.errno)
        }

        if pid == 0 {
            // ── Child process ──
            // Only async-signal-safe functions allowed here.
            // Set environment variables
            for envp in cEnv {
                guard let envp else { break }
                putenv(envp)
            }
            // Execute the binary
            execv(executablePath, cArgs)
            // If execv returns, it failed
            _exit(127)
        }

        // ── Parent process ──
        // Free allocated strings (parent copy)
        cArgs.forEach { $0.map { free($0) } }
        cEnv.forEach { $0.map { free($0) } }

        self.masterFD = master
        self.childPID = pid
        self.isRunning = true

        logger.info("PTY process launched: PID=\(pid), masterFD=\(master)")
    }

    // MARK: - Terminal Configuration

    /// Disable terminal echo and canonical mode.
    ///
    /// Without this, every command written to the PTY would be echoed back
    /// on the read side, mixing with the child's actual output.
    func configureTerminal() {
        guard masterFD >= 0 else { return }

        var termios = Darwin.termios()
        guard tcgetattr(masterFD, &termios) == 0 else {
            logger.warning("tcgetattr failed: \(Darwin.errno)")
            return
        }

        // Disable echo (ECHO) so input isn't reflected back
        termios.c_lflag &= ~UInt(ECHO)
        // Disable canonical mode (ICANON) for raw byte-by-byte delivery
        termios.c_lflag &= ~UInt(ICANON)

        guard tcsetattr(masterFD, TCSANOW, &termios) == 0 else {
            logger.warning("tcsetattr failed: \(Darwin.errno)")
            return
        }

        logger.info("PTY terminal configured: echo=off, canonical=off")
    }

    // MARK: - Reading

    /// Start reading output from the child process via GCD dispatch source.
    ///
    /// - Parameters:
    ///   - onData: Called with raw data chunks from the child's stdout.
    ///   - onEOF: Called when the child closes its output (typically on exit).
    func startReading(onData: @escaping @Sendable (Data) -> Void, onEOF: @escaping @Sendable () -> Void) {
        guard masterFD >= 0 else { return }

        let fd = masterFD
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ptyQueue)

        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(fd, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer.prefix(bytesRead))
                onData(data)
            } else if bytesRead == 0 {
                // EOF
                onEOF()
            } else {
                // Error — likely fd closed or process died
                let err = Darwin.errno
                if err != EAGAIN && err != EINTR {
                    onEOF()
                }
            }
        }

        source.setCancelHandler {
            // Source cancelled — nothing to clean up here,
            // fd is closed in terminate()
        }

        source.resume()
        self.readSource = source
    }

    // MARK: - Writing

    /// Write text to the child process's stdin via the PTY.
    ///
    /// - Parameter text: The text to send (should include `\n` if needed).
    /// - Returns: `true` if the write succeeded.
    @discardableResult
    func write(_ text: String) -> Bool {
        guard masterFD >= 0, isRunning else { return false }

        let fd = masterFD
        var bytes = Array(text.utf8)
        var totalWritten = 0

        while totalWritten < bytes.count {
            let n = Darwin.write(fd, &bytes[totalWritten], bytes.count - totalWritten)
            if n < 0 {
                let err = Darwin.errno
                if err == EINTR { continue }
                logger.error("PTY write failed: errno=\(err)")
                return false
            }
            totalWritten += n
        }

        return true
    }

    // MARK: - Lifecycle

    /// Terminate the child process and clean up resources.
    ///
    /// Sends SIGHUP first (standard terminal hangup), then SIGKILL after a brief wait.
    /// Always calls `waitpid()` to prevent zombie processes.
    func terminate() {
        guard childPID > 0 else { return }

        logger.info("Terminating PTY process PID=\(childPID)")

        // Cancel the read source first
        readSource?.cancel()
        readSource = nil

        let pid = childPID

        // Send SIGHUP (standard terminal hangup signal)
        kill(pid, SIGHUP)

        // Brief wait for graceful exit
        var status: Int32 = 0
        let waited = waitpid(pid, &status, WNOHANG)

        if waited == 0 {
            // Process still alive — give it a moment then force kill
            usleep(200_000) // 200ms
            let waited2 = waitpid(pid, &status, WNOHANG)
            if waited2 == 0 {
                kill(pid, SIGKILL)
                waitpid(pid, &status, 0) // Blocking wait to reap
            }
        }

        // Close the master fd
        if masterFD >= 0 {
            close(masterFD)
        }

        masterFD = -1
        childPID = -1
        isRunning = false

        logger.info("PTY process terminated and cleaned up")
    }

    /// Wait for the child process to exit. Blocking call.
    ///
    /// - Returns: The exit status of the child process.
    func waitForExit() -> Int32 {
        guard childPID > 0 else { return -1 }

        var status: Int32 = 0
        let pid = childPID
        waitpid(pid, &status, 0)

        isRunning = false

        // WIFEXITED/WEXITSTATUS are C macros not available in Swift — inline them.
        // On Darwin: WIFEXITED(s) = ((s & 0x7f) == 0), WEXITSTATUS(s) = ((s >> 8) & 0xff)
        // WIFSIGNALED(s) = ((s & 0x7f) != 0 && (s & 0x7f) != 0x7f), WTERMSIG(s) = (s & 0x7f)
        let termSignal = status & 0x7f
        if termSignal == 0 {
            // Normal exit
            return (status >> 8) & 0xff
        } else if termSignal != 0x7f {
            // Killed by signal
            return -(termSignal)
        }
        return status
    }

    deinit {
        if isRunning {
            terminate()
        }
    }
}
