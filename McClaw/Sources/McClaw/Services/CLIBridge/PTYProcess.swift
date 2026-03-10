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
    /// Fired when the process output has stabilized (silence = ready for input).
    nonisolated(unsafe) private var readyContinuation: CheckedContinuation<Void, Never>?
    nonisolated(unsafe) private var hasSignaledReady = false
    /// When the process was launched — used to enforce minimum startup time.
    nonisolated(unsafe) private var launchTime: DispatchTime = .now()
    /// Timer that fires when output has been silent long enough.
    nonisolated(unsafe) private var silenceTimer: DispatchSourceTimer?
    /// How long the output must be silent before we consider the process ready.
    /// Claude CLI renders its UI in bursts; 2 seconds of silence after the
    /// minimum startup time means it's done.
    private static let silenceThresholdSeconds: Double = 2.0
    /// Minimum seconds after launch (or last startup clock reset) before
    /// silence detection can trigger. Claude CLI's Node.js process needs time
    /// to boot — early silences during loading are false positives.
    /// After trust prompt confirmation, the real boot takes ~20-40s
    /// (auth check, migration notices, VS Code integration, etc.).
    private static let minimumStartupSeconds: Double = 20.0

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
        self.launchTime = .now()

        logger.info("PTY process launched: PID=\(pid), masterFD=\(master)")
    }

    // MARK: - Startup Clock

    /// Reset the startup clock. Call this after auto-confirming a blocking prompt
    /// (like the trust dialog) so the minimum startup timer restarts from now.
    /// This prevents premature readiness detection while Claude is still booting
    /// after the prompt was dismissed.
    func resetStartupClock() {
        launchTime = .now()
        hasSignaledReady = false
        silenceTimer?.cancel()
        silenceTimer = nil
        logger.info("PTY startup clock reset — minimum startup timer restarted")
    }

    // MARK: - Terminal Configuration

    /// Configure terminal flags for background operation.
    ///
    /// Disables echo, canonical mode, signal processing, and flow control
    /// to prevent interference with programmatic I/O.
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
        // Disable signal processing (ISIG) so \x03 doesn't generate SIGINT
        termios.c_lflag &= ~UInt(ISIG)
        // Disable software flow control (XON/XOFF)
        termios.c_iflag &= ~UInt(IXON)

        guard tcsetattr(masterFD, TCSANOW, &termios) == 0 else {
            logger.warning("tcsetattr failed: \(Darwin.errno)")
            return
        }

        logger.info("PTY terminal configured: echo=off, canonical=off, isig=off")
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

        source.setEventHandler { [self] in
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(fd, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer.prefix(bytesRead))
                onData(data)

                // Silence-based readiness: each time output arrives, reset the silence timer.
                // When the CLI stops producing output for N seconds, it means it's done
                // initializing and is waiting for user input → ready.
                if !self.hasSignaledReady {
                    self.resetSilenceTimer()
                }
            } else if bytesRead == 0 {
                // EOF
                self.signalReadyIfNeeded()
                onEOF()
            } else {
                // Error — likely fd closed or process died
                let err = Darwin.errno
                if err != EAGAIN && err != EINTR {
                    self.signalReadyIfNeeded()
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

    /// Wait until the process output has been silent for `silenceThresholdSeconds`,
    /// indicating the CLI has finished initializing and is ready for input.
    /// Times out after the specified duration to avoid blocking forever.
    func waitUntilReady(timeout: TimeInterval = 30) async {
        if hasSignaledReady { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if self.hasSignaledReady {
                continuation.resume()
                return
            }
            self.readyContinuation = continuation

            // Timeout fallback — if silence detection doesn't fire, proceed anyway
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                self.signalReadyIfNeeded()
            }
        }
    }

    /// Reset the silence timer. Called each time output arrives.
    /// When the timer fires (no output for N seconds AND minimum startup elapsed),
    /// the process is considered ready.
    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: ptyQueue)
        timer.schedule(deadline: .now() + Self.silenceThresholdSeconds)
        timer.setEventHandler { [self] in
            // Check if minimum startup time has elapsed
            let elapsed = DispatchTime.now().uptimeNanoseconds - self.launchTime.uptimeNanoseconds
            let elapsedSeconds = Double(elapsed) / 1_000_000_000

            if elapsedSeconds >= Self.minimumStartupSeconds {
                self.logger.info("PTY output silent for \(Self.silenceThresholdSeconds)s after \(String(format: "%.1f", elapsedSeconds))s uptime — process ready")
                self.signalReadyIfNeeded()
            } else {
                // Too early — Claude is still booting. Don't signal yet.
                // Schedule a deferred check at the minimum startup time.
                let remainingSeconds = Self.minimumStartupSeconds - elapsedSeconds + Self.silenceThresholdSeconds
                self.logger.debug("PTY silence too early (\(String(format: "%.1f", elapsedSeconds))s) — deferring check by \(String(format: "%.1f", remainingSeconds))s")
                self.scheduleDeferredReadyCheck(afterSeconds: remainingSeconds)
            }
        }
        timer.resume()
        silenceTimer = timer
    }

    /// Schedule a deferred ready check. Used when silence was detected too early
    /// (before minimum startup time). If no new output arrives by then, signal ready.
    private func scheduleDeferredReadyCheck(afterSeconds: Double) {
        silenceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: ptyQueue)
        timer.schedule(deadline: .now() + afterSeconds)
        timer.setEventHandler { [self] in
            self.logger.info("Deferred ready check fired — signaling ready")
            self.signalReadyIfNeeded()
        }
        timer.resume()
        silenceTimer = timer
    }

    /// Signal readiness if not already done (prevents double-resume).
    private func signalReadyIfNeeded() {
        if !hasSignaledReady {
            hasSignaledReady = true
            silenceTimer?.cancel()
            silenceTimer = nil
            readyContinuation?.resume()
            readyContinuation = nil
        }
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

        // Cancel timers and read source
        silenceTimer?.cancel()
        silenceTimer = nil
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
