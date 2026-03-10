import Foundation
import Logging
import McClawKit

/// Singleton coordinator for all canvas operations.
/// Manages canvas windows, file watching, and A2UI protocol.
@MainActor
@Observable
final class CanvasManager {
    static let shared = CanvasManager()

    private let logger = Logger(label: "ai.mcclaw.canvas")

    /// Active canvas window controller (one per session).
    private(set) var activeController: CanvasWindowController?

    /// File watcher for hot-reload.
    private let fileWatcher = CanvasFileWatcher()

    /// Whether a canvas panel is currently visible.
    var isCanvasVisible: Bool {
        activeController?.isVisible ?? false
    }

    /// Current session key.
    private(set) var currentSessionKey: String?

    /// Base directory for canvas content (~/.mcclaw/).
    private var baseDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
    }

    private init() {}

    // MARK: - Canvas Lifecycle

    /// Show the canvas for a session, optionally navigating to a URL.
    func show(sessionKey: String, url: String? = nil, placement: CanvasPlacementParams? = nil) {
        // Reuse or create controller
        if activeController?.sessionKey != sessionKey {
            activeController?.close()
            activeController = CanvasWindowController(sessionKey: sessionKey)
            currentSessionKey = sessionKey

            // Setup file watcher for this session
            let sessionDir = canvasSessionDirectory(sessionKey: sessionKey, baseDir: baseDirectory)
            fileWatcher.watch(directory: sessionDir)
            fileWatcher.onFilesChanged = { [weak self] in
                self?.handleFileChange()
            }
        }

        if let url, let parsedURL = URL(string: url) {
            activeController?.navigate(to: parsedURL)
        } else {
            // Navigate to session's index.html via custom scheme
            activeController?.navigateToSession()
        }

        activeController?.show(placement: placement)
        logger.info("Canvas shown for session \(sessionKey)")
    }

    /// Hide the canvas.
    func hide() {
        activeController?.hide()
        logger.info("Canvas hidden")
    }

    /// Close and release the canvas.
    func close() {
        fileWatcher.stop()
        activeController?.close()
        activeController = nil
        currentSessionKey = nil
        logger.info("Canvas closed")
    }

    // MARK: - Navigation

    /// Navigate the canvas to a URL.
    func navigate(url: String) {
        guard let parsedURL = URL(string: url) else {
            logger.error("Invalid canvas URL: \(url)")
            return
        }
        activeController?.navigate(to: parsedURL)
    }

    // MARK: - JavaScript Evaluation

    /// Evaluate JavaScript in the canvas.
    func eval(javaScript: String) async throws -> Any? {
        guard let controller = activeController else {
            throw NodeError(code: .unavailable, message: "No active canvas")
        }
        return try await controller.evaluateJavaScript(javaScript)
    }

    // MARK: - Snapshot

    /// Take a snapshot of the canvas.
    func snapshot(maxWidth: Int? = nil, quality: Double? = nil, format: CanvasSnapshotFormat? = nil) async throws -> Data {
        guard let controller = activeController else {
            throw NodeError(code: .unavailable, message: "No active canvas")
        }
        return try await controller.takeSnapshot(maxWidth: maxWidth, quality: quality, format: format)
    }

    // MARK: - A2UI Protocol

    /// Handle an A2UI action from the canvas JavaScript bridge.
    func handleA2UIAction(actionName: String, surfaceId: String, sourceComponentId: String, message: String) async {
        logger.info("A2UI action received: \(actionName)")

        // Forward to Gateway as an agent message
        do {
            try await GatewayConnectionService.shared.sendCanvasA2UIAction(message: message)
        } catch {
            logger.error("Failed to send A2UI action: \(error)")
        }
    }

    /// Push A2UI messages to the canvas.
    func a2uiPush(messages: [[String: Any]]) async {
        guard let controller = activeController else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: messages),
              let json = String(data: data, encoding: .utf8) else { return }

        let script = "document.dispatchEvent(new CustomEvent('a2ui:push', { detail: \(json) }));"
        _ = try? await controller.evaluateJavaScript(script)
    }

    /// Push A2UI JSONL to the canvas.
    func a2uiPushJSONL(jsonl: String) async {
        guard let controller = activeController else { return }
        let escaped = jsonl.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = "document.dispatchEvent(new CustomEvent('a2ui:pushJSONL', { detail: '\(escaped)' }));"
        _ = try? await controller.evaluateJavaScript(script)
    }

    /// Reset A2UI state on the canvas.
    func a2uiReset() async {
        guard let controller = activeController else { return }
        let script = "document.dispatchEvent(new CustomEvent('a2ui:reset'));"
        _ = try? await controller.evaluateJavaScript(script)
    }

    // MARK: - Node Command Handling

    /// Handle a canvas-related bridge invoke request.
    func handleBridgeInvoke(_ request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        let sessionKey = AppState.shared.currentSessionId ?? "main"

        switch request.command {
        case "canvas.present":
            let params = request.decodeParams(CanvasPresentParams.self)
            show(sessionKey: sessionKey, url: params?.url, placement: params?.placement)
            return .success(id: request.id)

        case "canvas.hide":
            hide()
            return .success(id: request.id)

        case "canvas.navigate":
            guard let params = request.decodeParams(CanvasNavigateParams.self) else {
                return .failure(id: request.id, code: .invalidRequest, message: "Missing url parameter")
            }
            navigate(url: params.url)
            return .success(id: request.id)

        case "canvas.eval":
            guard let params = request.decodeParams(CanvasEvalParams.self) else {
                return .failure(id: request.id, code: .invalidRequest, message: "Missing javaScript parameter")
            }
            do {
                let result = try await eval(javaScript: params.javaScript)
                let resultStr = result.map { "\($0)" } ?? "null"
                return .success(id: request.id, payload: CanvasEvalResult(result: resultStr))
            } catch {
                return .failure(id: request.id, code: .internalError, message: error.localizedDescription)
            }

        case "canvas.snapshot":
            let params = request.decodeParams(CanvasSnapshotParams.self)
            do {
                let data = try await snapshot(maxWidth: params?.maxWidth, quality: params?.quality, format: params?.format)
                let base64 = data.base64EncodedString()
                let mime = (params?.format ?? .png) == .png ? "image/png" : "image/jpeg"
                let result = CanvasSnapshotResult(data: base64, mimeType: mime, size: data.count)
                return .success(id: request.id, payload: result)
            } catch {
                return .failure(id: request.id, code: .internalError, message: error.localizedDescription)
            }

        case "canvas.a2ui.push":
            // paramsJSON contains { messages: [...] }
            if let json = request.paramsJSON,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messages = dict["messages"] as? [[String: Any]] {
                await a2uiPush(messages: messages)
            }
            return .success(id: request.id)

        case "canvas.a2ui.pushJSONL":
            if let json = request.paramsJSON,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let jsonl = dict["jsonl"] as? String {
                await a2uiPushJSONL(jsonl: jsonl)
            }
            return .success(id: request.id)

        case "canvas.a2ui.reset":
            await a2uiReset()
            return .success(id: request.id)

        default:
            return .failure(id: request.id, code: .invalidRequest, message: "Unknown canvas command: \(request.command)")
        }
    }

    // MARK: - File Watcher

    private func handleFileChange() {
        logger.debug("Canvas files changed, reloading")
        activeController?.navigateToSession()
    }
}

// MARK: - Response Types

struct CanvasSnapshotResult: Codable, Sendable {
    let data: String
    let mimeType: String
    let size: Int
}

struct CanvasEvalResult: Codable, Sendable {
    let result: String
}
