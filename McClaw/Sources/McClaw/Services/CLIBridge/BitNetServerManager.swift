import Foundation
import Logging
import McClawKit

/// Runs BitNet inference using `llama-cli` directly (like `run_inference.py`).
/// Each `chatStream()` call spawns a llama-cli process and streams stdout in real time.
/// This approach works reliably with BitNet quantized models (unlike llama-server
/// which returns empty content for i2_s models).
actor BitNetServerManager {
    static let shared = BitNetServerManager()

    private let logger = Logger(label: "ai.mcclaw.bitnet")
    private var config = BitNetKit.ServerConfig()
    private var currentModel: String?

    /// Whether BitNet is ready (binary exists and model is set).
    var isRunning: Bool {
        currentModel != nil &&
        FileManager.default.isExecutableFile(atPath: BitNetKit.Paths.binary)
    }

    /// Record activity (no-op now, kept for API compatibility).
    func touch() {}

    /// Prepare BitNet for the given model (validates binary exists).
    func start(
        model: String,
        config: BitNetKit.ServerConfig = BitNetKit.ServerConfig(),
        trackIdle: Bool = false
    ) async throws {
        self.config = config
        self.currentModel = model

        let binaryPath = BitNetKit.Paths.binary
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw BitNetError.binaryNotFound(binaryPath)
        }

        let modelPath = BitNetKit.Paths.resolveModelPath(model)
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw BitNetError.modelNotFound(modelPath)
        }

        logger.info("BitNet ready: model=\(model), binary=\(binaryPath)")
    }

    /// Stop BitNet (clears model selection).
    func stop() async {
        currentModel = nil
    }

    /// Stream a response from BitNet via llama-cli.
    /// Yields text chunks as they are produced by llama-cli in real time.
    func chatStream(message: String, systemPrompt: String? = nil) throws -> AsyncStream<String> {
        guard let model = currentModel else {
            throw BitNetError.notReady
        }

        let modelPath = BitNetKit.Paths.resolveModelPath(model)
        let binaryPath = BitNetKit.Paths.binary

        // Build prompt using Falcon3 Instruct chat template tokens.
        // Without proper template, the model generates degenerate/looping text.
        var prompt = ""
        if let systemPrompt, !systemPrompt.isEmpty {
            prompt += "<|system|>\n\(systemPrompt)\n"
        }
        prompt += "<|user|>\n\(message)\n<|assistant|>\n"

        let args: [String] = [
            "-m", modelPath,
            "-n", String(config.maxTokens),
            "-t", String(config.threads),
            "-p", prompt,
            "--special",  // parse <|user|> etc. as real tokens, not text
            "-ngl", "0",
            "-c", String(config.contextSize),
            "--temp", String(config.temperature),
            "--repeat-penalty", "1.3",
            "-b", "1",
            "--no-display-prompt",
            "--log-verbosity", "0",
        ]

        logger.info("BitNet streaming: model=\(model), tokens=\(config.maxTokens)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: BitNetKit.Paths.home)

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        // Thread-safe flag to stop generation when a special token is detected.
        let stopGuard = StopGuard()

        return AsyncStream { continuation in
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty || stopGuard.stopped {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    if !stopGuard.stopped {
                        stopGuard.stopped = true
                        continuation.finish()
                    }
                    return
                }
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    // Stop at special tokens. Different GGUF models emit
                    // different representations: <|user|>, </|>, >>UNUSED_0<<, etc.
                    let stopMarkers = ["<|", "</|", ">>UNUSED"]
                    var earliest: String.Index?
                    for marker in stopMarkers {
                        if let range = text.range(of: marker) {
                            if earliest == nil || range.lowerBound < earliest! {
                                earliest = range.lowerBound
                            }
                        }
                    }
                    if let cutoff = earliest {
                        let usable = String(text[text.startIndex..<cutoff])
                            .replacingOccurrences(of: "<br/>", with: "\n")
                            .replacingOccurrences(of: "<br>", with: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !usable.isEmpty {
                            continuation.yield(usable)
                        }
                        stopGuard.stopped = true
                        process.terminate()
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.finish()
                        return
                    }
                    // Clean HTML line breaks from streaming chunks too
                    let cleaned = text
                        .replacingOccurrences(of: "<br/>", with: "\n")
                        .replacingOccurrences(of: "<br>", with: "\n")
                    continuation.yield(cleaned)
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                continuation.yield("[Error] Failed to start BitNet: \(error.localizedDescription)")
                continuation.finish()
            }
        }
    }
}

/// Thread-safe mutable flag for use in Sendable closures.
private final class StopGuard: Sendable {
    // Using a lock-free atomic isn't available in Swift 5/6 without import Synchronization,
    // but since readabilityHandler runs on a single serial dispatch queue per file handle,
    // this is safe in practice. We use nonisolated(unsafe) to satisfy Sendable.
    nonisolated(unsafe) var stopped = false
}

/// Errors from BitNet inference.
enum BitNetError: Error, LocalizedError {
    case binaryNotFound(String)
    case modelNotFound(String)
    case notReady
    case processStartFailed(String)
    case inferenceError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            "llama-cli not found at \(path). Install BitNet first."
        case .modelNotFound(let path):
            "Model not found at \(path). Download a model first."
        case .notReady:
            "BitNet is not ready. Select a model first."
        case .processStartFailed(let reason):
            "Failed to start BitNet: \(reason)"
        case .inferenceError(let detail):
            "BitNet inference error: \(detail)"
        case .invalidResponse:
            "Invalid response from BitNet."
        }
    }
}
