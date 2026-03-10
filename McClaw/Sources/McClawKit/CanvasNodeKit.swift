import Foundation

// MARK: - Canvas Commands

/// Canvas command identifiers matching Gateway protocol.
public enum CanvasCommand: String, Sendable {
    case present = "canvas.present"
    case hide = "canvas.hide"
    case navigate = "canvas.navigate"
    case eval = "canvas.eval"
    case snapshot = "canvas.snapshot"
}

/// A2UI (Agent-to-UI) command identifiers.
public enum CanvasA2UICommand: String, Sendable {
    case push = "canvas.a2ui.push"
    case pushJSONL = "canvas.a2ui.pushJSONL"
    case reset = "canvas.a2ui.reset"
}

/// Canvas placement parameters.
public struct CanvasPlacementParams: Codable, Sendable {
    public var x: Double?
    public var y: Double?
    public var width: Double?
    public var height: Double?

    public init(x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Parameters for canvas.present command.
public struct CanvasPresentParams: Codable, Sendable {
    public var url: String?
    public var placement: CanvasPlacementParams?

    public init(url: String? = nil, placement: CanvasPlacementParams? = nil) {
        self.url = url
        self.placement = placement
    }
}

/// Parameters for canvas.navigate command.
public struct CanvasNavigateParams: Codable, Sendable {
    public var url: String

    public init(url: String) {
        self.url = url
    }
}

/// Parameters for canvas.eval command.
public struct CanvasEvalParams: Codable, Sendable {
    public var javaScript: String

    public init(javaScript: String) {
        self.javaScript = javaScript
    }
}

/// Parameters for canvas.snapshot command.
public struct CanvasSnapshotParams: Codable, Sendable {
    public var maxWidth: Int?
    public var quality: Double?
    public var format: CanvasSnapshotFormat?

    public init(maxWidth: Int? = nil, quality: Double? = nil, format: CanvasSnapshotFormat? = nil) {
        self.maxWidth = maxWidth
        self.quality = quality
        self.format = format
    }
}

/// Snapshot image format.
public enum CanvasSnapshotFormat: String, Codable, Sendable {
    case png
    case jpeg
}

// MARK: - Node Commands

/// Node command categories.
public enum NodeCommandCategory: String, Sendable {
    case canvas
    case camera
    case screen
    case system
    case location
    case browser
}

/// Camera command identifiers.
public enum CameraCommand: String, Sendable {
    case list = "camera.list"
    case snap = "camera.snap"
    case clip = "camera.clip"
}

/// Camera facing direction.
public enum CameraFacing: String, Codable, Sendable {
    case front
    case back
}

/// Parameters for camera.snap command.
public struct CameraSnapParams: Codable, Sendable {
    public var facing: CameraFacing?
    public var maxWidth: Int?
    public var quality: Double?
    public var deviceId: String?
    public var delayMs: Int?

    public init(facing: CameraFacing? = nil, maxWidth: Int? = nil, quality: Double? = nil,
                deviceId: String? = nil, delayMs: Int? = nil) {
        self.facing = facing
        self.maxWidth = maxWidth
        self.quality = quality
        self.deviceId = deviceId
        self.delayMs = delayMs
    }
}

/// Parameters for camera.clip command.
public struct CameraClipParams: Codable, Sendable {
    public var facing: CameraFacing?
    public var durationMs: Int?
    public var includeAudio: Bool?
    public var deviceId: String?

    public init(facing: CameraFacing? = nil, durationMs: Int? = nil, includeAudio: Bool? = nil,
                deviceId: String? = nil) {
        self.facing = facing
        self.durationMs = durationMs
        self.includeAudio = includeAudio
        self.deviceId = deviceId
    }
}

/// Camera device information.
public struct CameraDeviceInfo: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var position: CameraFacing?

    public init(id: String, name: String, position: CameraFacing? = nil) {
        self.id = id
        self.name = name
        self.position = position
    }
}

/// Screen command identifiers.
public enum ScreenCommand: String, Sendable {
    case record = "screen.record"
}

/// Parameters for screen.record command.
public struct ScreenRecordParams: Codable, Sendable {
    public var screenIndex: Int?
    public var durationMs: Int?
    public var fps: Double?
    public var includeAudio: Bool?

    public init(screenIndex: Int? = nil, durationMs: Int? = nil, fps: Double? = nil,
                includeAudio: Bool? = nil) {
        self.screenIndex = screenIndex
        self.durationMs = durationMs
        self.fps = fps
        self.includeAudio = includeAudio
    }
}

/// System command identifiers.
public enum SystemCommand: String, Sendable {
    case run = "system.run"
    case which = "system.which"
    case notify = "system.notify"
}

/// Location command identifiers.
public enum LocationCommand: String, Sendable {
    case get = "location.get"
}

// MARK: - Bridge Protocol

/// A node invoke request from the Gateway.
public struct BridgeInvokeRequest: Codable, Sendable {
    public var type: String
    public var id: String
    public var command: String
    public var paramsJSON: String?

    public init(type: String = "invoke", id: String, command: String, paramsJSON: String? = nil) {
        self.type = type
        self.id = id
        self.command = command
        self.paramsJSON = paramsJSON
    }

    /// Decode params JSON into a specific type.
    public func decodeParams<T: Decodable>(_ type: T.Type) -> T? {
        guard let json = paramsJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// A node invoke response to the Gateway.
public struct BridgeInvokeResponse: Codable, Sendable {
    public var type: String
    public var id: String
    public var ok: Bool
    public var payloadJSON: String?
    public var error: NodeError?

    public init(type: String = "invoke-res", id: String, ok: Bool,
                payloadJSON: String? = nil, error: NodeError? = nil) {
        self.type = type
        self.id = id
        self.ok = ok
        self.payloadJSON = payloadJSON
        self.error = error
    }

    /// Create a success response with an encodable payload.
    public static func success<T: Encodable>(id: String, payload: T) -> BridgeInvokeResponse {
        let json = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
        return BridgeInvokeResponse(id: id, ok: true, payloadJSON: json)
    }

    /// Create a success response with no payload.
    public static func success(id: String) -> BridgeInvokeResponse {
        BridgeInvokeResponse(id: id, ok: true)
    }

    /// Create an error response.
    public static func failure(id: String, code: NodeErrorCode, message: String) -> BridgeInvokeResponse {
        BridgeInvokeResponse(id: id, ok: false, error: NodeError(code: code, message: message))
    }
}

/// A node event frame sent to the Gateway.
public struct BridgeEventFrame: Codable, Sendable {
    public var type: String
    public var event: String
    public var payloadJSON: String?

    public init(type: String = "event", event: String, payloadJSON: String? = nil) {
        self.type = type
        self.event = event
        self.payloadJSON = payloadJSON
    }
}

/// Node hello frame announcing capabilities.
public struct BridgeHello: Codable, Sendable {
    public var type: String
    public var nodeId: String
    public var displayName: String?
    public var caps: [String]?
    public var commands: [String]?

    public init(type: String = "hello", nodeId: String, displayName: String? = nil,
                caps: [String]? = nil, commands: [String]? = nil) {
        self.type = type
        self.nodeId = nodeId
        self.displayName = displayName
        self.caps = caps
        self.commands = commands
    }
}

/// Node error codes.
public enum NodeErrorCode: String, Codable, Sendable {
    case invalidRequest
    case unavailable
    case permissionDenied
    case timeout
    case internalError
}

/// Node error structure.
public struct NodeError: Error, Codable, Sendable {
    public var code: NodeErrorCode
    public var message: String

    public init(code: NodeErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - Canvas Helpers

/// Sanitize a session key for use as a directory name.
public func sanitizeSessionKey(_ key: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return String(key.unicodeScalars.filter { allowed.contains($0) })
}

/// Build the canvas session directory path.
public func canvasSessionDirectory(sessionKey: String, baseDir: URL) -> URL {
    baseDir.appendingPathComponent("canvas")
        .appendingPathComponent(sanitizeSessionKey(sessionKey))
}

/// Determine MIME type from file extension.
public func mimeTypeForExtension(_ ext: String) -> String {
    switch ext.lowercased() {
    case "html", "htm": return "text/html"
    case "css": return "text/css"
    case "js", "mjs": return "application/javascript"
    case "json": return "application/json"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "svg": return "image/svg+xml"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    case "ico": return "image/x-icon"
    case "webp": return "image/webp"
    case "mp4": return "video/mp4"
    case "webm": return "video/webm"
    case "mp3": return "audio/mpeg"
    case "wav": return "audio/wav"
    case "txt": return "text/plain"
    case "xml": return "application/xml"
    case "pdf": return "application/pdf"
    default: return "application/octet-stream"
    }
}

/// Parse a node command string into category and action.
public func parseNodeCommand(_ command: String) -> (category: NodeCommandCategory, action: String)? {
    let parts = command.split(separator: ".", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    let prefix = String(parts[0])
    let action = String(parts[1])

    switch prefix {
    case "canvas": return (.canvas, action)
    case "camera": return (.camera, action)
    case "screen": return (.screen, action)
    case "system": return (.system, action)
    case "location": return (.location, action)
    case "browser": return (.browser, action)
    default: return nil
    }
}

/// Build the list of supported node commands.
public func buildNodeCommandList(cameraEnabled: Bool, screenEnabled: Bool) -> [String] {
    var commands = [
        "canvas.present", "canvas.hide", "canvas.navigate", "canvas.eval", "canvas.snapshot",
        "canvas.a2ui.push", "canvas.a2ui.pushJSONL", "canvas.a2ui.reset",
        "system.run", "system.which", "system.notify",
        "location.get",
    ]

    if cameraEnabled {
        commands.append(contentsOf: ["camera.list", "camera.snap", "camera.clip"])
    }
    if screenEnabled {
        commands.append(contentsOf: ["screen.record"])
    }

    return commands
}

/// Build the list of node capabilities.
public func buildNodeCapabilities(cameraEnabled: Bool, screenEnabled: Bool) -> [String] {
    var caps = ["Canvas"]
    if cameraEnabled { caps.append("Camera") }
    if screenEnabled { caps.append("ScreenRecord") }
    return caps
}
