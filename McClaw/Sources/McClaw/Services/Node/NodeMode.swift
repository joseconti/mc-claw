import Foundation
import UserNotifications
import Logging
import McClawKit

/// Node mode: exposes macOS capabilities to the Gateway.
/// Routes bridge invoke requests to the appropriate service.
@MainActor
@Observable
final class NodeMode {
    static let shared = NodeMode()

    private let logger = Logger(label: "ai.mcclaw.node")

    /// Whether node mode is active (connected to Gateway as a node).
    var isActive: Bool = false

    /// Whether camera capture is enabled by the user.
    var cameraEnabled: Bool = false

    /// Whether screen recording is enabled by the user.
    var screenEnabled: Bool = true

    /// Node ID for this instance.
    let nodeId = "mcclaw-\(ProcessInfo.processInfo.processIdentifier)"

    private init() {}

    // MARK: - Capabilities

    /// Build the hello frame for this node.
    func buildHello() -> BridgeHello {
        BridgeHello(
            nodeId: nodeId,
            displayName: Host.current().localizedName ?? "McClaw",
            caps: buildNodeCapabilities(cameraEnabled: cameraEnabled, screenEnabled: screenEnabled),
            commands: buildNodeCommandList(cameraEnabled: cameraEnabled, screenEnabled: screenEnabled)
        )
    }

    /// Available node capabilities for display.
    var capabilities: [NodeCapability] {
        var caps = [
            NodeCapability(id: "canvas", description: String(localized: "Canvas panel with A2UI protocol", bundle: .appModule)),
            NodeCapability(id: "system.run", description: String(localized: "Execute system commands", bundle: .appModule)),
            NodeCapability(id: "location.get", description: String(localized: "Get current location", bundle: .appModule)),
        ]
        if cameraEnabled {
            caps.append(NodeCapability(id: "camera", description: String(localized: "Capture photos and video", bundle: .appModule)))
        }
        if screenEnabled {
            caps.append(NodeCapability(id: "screen.record", description: String(localized: "Record screen", bundle: .appModule)))
        }
        return caps
    }

    // MARK: - Command Dispatch

    /// Handle a bridge invoke request from the Gateway.
    func handleInvoke(_ request: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        logger.info("Node invoke: \(request.command) (id: \(request.id))")

        // Canvas commands may have multiple dots (canvas.a2ui.push)
        if request.command.hasPrefix("canvas.") {
            return await CanvasManager.shared.handleBridgeInvoke(request)
        }

        guard let parsed = parseNodeCommand(request.command) else {
            return .failure(id: request.id, code: .invalidRequest, message: "Unknown command: \(request.command)")
        }

        switch parsed.category {
        case .canvas:
            return await CanvasManager.shared.handleBridgeInvoke(request)

        case .camera:
            return await handleCameraCommand(request, action: parsed.action)

        case .screen:
            return await handleScreenCommand(request, action: parsed.action)

        case .system:
            return await handleSystemCommand(request, action: parsed.action)

        case .location:
            return await handleLocationCommand(request, action: parsed.action)

        case .browser:
            return .failure(id: request.id, code: .unavailable, message: "Browser proxy not implemented")
        }
    }

    // MARK: - Camera Commands

    private func handleCameraCommand(_ request: BridgeInvokeRequest, action: String) async -> BridgeInvokeResponse {
        guard cameraEnabled else {
            return .failure(id: request.id, code: .permissionDenied, message: "Camera not enabled in settings")
        }

        switch action {
        case "list":
            let devices = await CameraCaptureService.shared.listDevices()
            return .success(id: request.id, payload: devices)

        case "snap":
            let params = request.decodeParams(CameraSnapParams.self) ?? CameraSnapParams()
            do {
                let result = try await CameraCaptureService.shared.snap(params: params)
                let base64 = result.data.base64EncodedString()
                return .success(id: request.id, payload: CameraSnapResult(
                    data: base64, mimeType: "image/jpeg",
                    width: result.width, height: result.height, size: result.data.count
                ))
            } catch let error as NodeError {
                return .failure(id: request.id, code: error.code, message: error.message)
            } catch {
                return .failure(id: request.id, code: .internalError, message: error.localizedDescription)
            }

        case "clip":
            let params = request.decodeParams(CameraClipParams.self) ?? CameraClipParams()
            do {
                let result = try await CameraCaptureService.shared.clip(params: params)
                let fileData = try Data(contentsOf: URL(fileURLWithPath: result.path))
                let base64 = fileData.base64EncodedString()
                try? FileManager.default.removeItem(atPath: result.path)
                return .success(id: request.id, payload: CameraClipResult(
                    data: base64, mimeType: "video/mp4",
                    durationMs: result.durationMs,
                    width: result.width, height: result.height, size: fileData.count
                ))
            } catch let error as NodeError {
                return .failure(id: request.id, code: error.code, message: error.message)
            } catch {
                return .failure(id: request.id, code: .internalError, message: error.localizedDescription)
            }

        default:
            return .failure(id: request.id, code: .invalidRequest, message: "Unknown camera command: camera.\(action)")
        }
    }

    // MARK: - Screen Commands

    private func handleScreenCommand(_ request: BridgeInvokeRequest, action: String) async -> BridgeInvokeResponse {
        guard screenEnabled else {
            return .failure(id: request.id, code: .permissionDenied, message: "Screen recording not enabled")
        }

        switch action {
        case "record":
            let params = request.decodeParams(ScreenRecordParams.self) ?? ScreenRecordParams()
            do {
                let result = try await ScreenRecordService.shared.record(params: params)
                let fileData = try Data(contentsOf: URL(fileURLWithPath: result.path))
                let base64 = fileData.base64EncodedString()
                try? FileManager.default.removeItem(atPath: result.path)
                return .success(id: request.id, payload: ScreenRecordResult(
                    data: base64, mimeType: "video/mp4",
                    durationMs: result.durationMs, size: fileData.count
                ))
            } catch let error as NodeError {
                return .failure(id: request.id, code: error.code, message: error.message)
            } catch {
                return .failure(id: request.id, code: .internalError, message: error.localizedDescription)
            }

        default:
            return .failure(id: request.id, code: .invalidRequest, message: "Unknown screen command: screen.\(action)")
        }
    }

    // MARK: - System Commands

    private func handleSystemCommand(_ request: BridgeInvokeRequest, action: String) async -> BridgeInvokeResponse {
        switch action {
        case "run":
            return .failure(id: request.id, code: .unavailable,
                            message: "system.run delegated to exec approvals flow")

        case "which":
            if let json = request.paramsJSON,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let command = dict["command"] as? String {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                process.arguments = [command]
                let pipe = Pipe()
                process.standardOutput = pipe
                try? process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0 && !output.isEmpty {
                    return .success(id: request.id, payload: SystemWhichResult(path: output))
                }
                return .failure(id: request.id, code: .unavailable, message: "Command not found: \(command)")
            }
            return .failure(id: request.id, code: .invalidRequest, message: "Missing command parameter")

        case "notify":
            if let json = request.paramsJSON,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let title = dict["title"] as? String ?? "McClaw"
                let body = dict["body"] as? String ?? ""
                sendNotification(title: title, body: body)
                return .success(id: request.id)
            }
            return .failure(id: request.id, code: .invalidRequest, message: "Missing notification parameters")

        default:
            return .failure(id: request.id, code: .invalidRequest,
                            message: "Unknown system command: system.\(action)")
        }
    }

    // MARK: - Location Commands

    private func handleLocationCommand(_ request: BridgeInvokeRequest, action: String) async -> BridgeInvokeResponse {
        switch action {
        case "get":
            return await NodeLocationService.shared.getLocation(requestId: request.id)
        default:
            return .failure(id: request.id, code: .invalidRequest,
                            message: "Unknown location command: location.\(action)")
        }
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// A capability that this node can provide.
struct NodeCapability: Identifiable, Codable, Sendable {
    let id: String
    let description: String
}

// MARK: - Response Types

struct CameraSnapResult: Codable, Sendable {
    let data: String
    let mimeType: String
    let width: Int
    let height: Int
    let size: Int
}

struct CameraClipResult: Codable, Sendable {
    let data: String
    let mimeType: String
    let durationMs: Int
    let width: Int
    let height: Int
    let size: Int
}

struct ScreenRecordResult: Codable, Sendable {
    let data: String
    let mimeType: String
    let durationMs: Int
    let size: Int
}

struct SystemWhichResult: Codable, Sendable {
    let path: String
}
