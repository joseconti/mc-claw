import Foundation
import Testing
@testable import McClawKit

@Suite("CanvasNodeKit Tests")
struct CanvasNodeKitTests {

    // MARK: - sanitizeSessionKey

    @Test("sanitizeSessionKey removes special characters")
    func sanitizeSessionKey_basic() {
        #expect(sanitizeSessionKey("hello-world_123") == "hello-world_123")
        #expect(sanitizeSessionKey("session/with:bad chars!") == "sessionwithbadchars")
        #expect(sanitizeSessionKey("../../../etc/passwd") == "etcpasswd")
        #expect(sanitizeSessionKey("") == "")
        #expect(sanitizeSessionKey("abc 123") == "abc123")
    }

    @Test("sanitizeSessionKey preserves alphanumeric and dash/underscore")
    func sanitizeSessionKey_preserves() {
        let key = "McClaw-Session_2024-01-15"
        #expect(sanitizeSessionKey(key) == "McClaw-Session_2024-01-15")
    }

    // MARK: - canvasSessionDirectory

    @Test("canvasSessionDirectory builds correct path")
    func canvasSessionDir() {
        let base = URL(fileURLWithPath: "/Users/test/.mcclaw")
        let dir = canvasSessionDirectory(sessionKey: "my-session", baseDir: base)
        #expect(dir.path == "/Users/test/.mcclaw/canvas/my-session")
    }

    @Test("canvasSessionDirectory sanitizes key")
    func canvasSessionDir_sanitized() {
        let base = URL(fileURLWithPath: "/tmp")
        let dir = canvasSessionDirectory(sessionKey: "bad/key", baseDir: base)
        #expect(dir.path == "/tmp/canvas/badkey")
    }

    // MARK: - mimeTypeForExtension

    @Test("mimeTypeForExtension returns correct MIME types")
    func mimeTypes() {
        #expect(mimeTypeForExtension("html") == "text/html")
        #expect(mimeTypeForExtension("htm") == "text/html")
        #expect(mimeTypeForExtension("css") == "text/css")
        #expect(mimeTypeForExtension("js") == "application/javascript")
        #expect(mimeTypeForExtension("json") == "application/json")
        #expect(mimeTypeForExtension("png") == "image/png")
        #expect(mimeTypeForExtension("jpg") == "image/jpeg")
        #expect(mimeTypeForExtension("jpeg") == "image/jpeg")
        #expect(mimeTypeForExtension("svg") == "image/svg+xml")
        #expect(mimeTypeForExtension("mp4") == "video/mp4")
        #expect(mimeTypeForExtension("mp3") == "audio/mpeg")
        #expect(mimeTypeForExtension("pdf") == "application/pdf")
        #expect(mimeTypeForExtension("woff2") == "font/woff2")
    }

    @Test("mimeTypeForExtension case insensitive")
    func mimeTypes_caseInsensitive() {
        #expect(mimeTypeForExtension("HTML") == "text/html")
        #expect(mimeTypeForExtension("PNG") == "image/png")
        #expect(mimeTypeForExtension("JS") == "application/javascript")
    }

    @Test("mimeTypeForExtension unknown returns octet-stream")
    func mimeTypes_unknown() {
        #expect(mimeTypeForExtension("xyz") == "application/octet-stream")
        #expect(mimeTypeForExtension("") == "application/octet-stream")
    }

    // MARK: - parseNodeCommand

    @Test("parseNodeCommand parses valid commands")
    func parseCommand_valid() {
        let canvas = parseNodeCommand("canvas.present")
        #expect(canvas?.category == .canvas)
        #expect(canvas?.action == "present")

        let camera = parseNodeCommand("camera.snap")
        #expect(camera?.category == .camera)
        #expect(camera?.action == "snap")

        let screen = parseNodeCommand("screen.record")
        #expect(screen?.category == .screen)
        #expect(screen?.action == "record")

        let system = parseNodeCommand("system.run")
        #expect(system?.category == .system)
        #expect(system?.action == "run")

        let location = parseNodeCommand("location.get")
        #expect(location?.category == .location)
        #expect(location?.action == "get")
    }

    @Test("parseNodeCommand returns nil for invalid commands")
    func parseCommand_invalid() {
        #expect(parseNodeCommand("unknown.command") == nil)
        #expect(parseNodeCommand("noprefix") == nil)
        #expect(parseNodeCommand("") == nil)
    }

    // MARK: - buildNodeCommandList

    @Test("buildNodeCommandList includes base commands")
    func commandList_base() {
        let commands = buildNodeCommandList(cameraEnabled: false, screenEnabled: false)
        #expect(commands.contains("canvas.present"))
        #expect(commands.contains("canvas.hide"))
        #expect(commands.contains("canvas.eval"))
        #expect(commands.contains("system.run"))
        #expect(commands.contains("location.get"))
        #expect(!commands.contains("camera.snap"))
        #expect(!commands.contains("screen.record"))
    }

    @Test("buildNodeCommandList includes camera when enabled")
    func commandList_camera() {
        let commands = buildNodeCommandList(cameraEnabled: true, screenEnabled: false)
        #expect(commands.contains("camera.list"))
        #expect(commands.contains("camera.snap"))
        #expect(commands.contains("camera.clip"))
        #expect(!commands.contains("screen.record"))
    }

    @Test("buildNodeCommandList includes screen when enabled")
    func commandList_screen() {
        let commands = buildNodeCommandList(cameraEnabled: false, screenEnabled: true)
        #expect(commands.contains("screen.record"))
        #expect(!commands.contains("camera.snap"))
    }

    @Test("buildNodeCommandList includes all when both enabled")
    func commandList_all() {
        let commands = buildNodeCommandList(cameraEnabled: true, screenEnabled: true)
        #expect(commands.contains("camera.snap"))
        #expect(commands.contains("screen.record"))
        #expect(commands.contains("canvas.present"))
        #expect(commands.contains("system.run"))
    }

    // MARK: - buildNodeCapabilities

    @Test("buildNodeCapabilities returns correct caps")
    func capabilities() {
        let none = buildNodeCapabilities(cameraEnabled: false, screenEnabled: false)
        #expect(none == ["Canvas"])

        let camera = buildNodeCapabilities(cameraEnabled: true, screenEnabled: false)
        #expect(camera == ["Canvas", "Camera"])

        let screen = buildNodeCapabilities(cameraEnabled: false, screenEnabled: true)
        #expect(screen == ["Canvas", "ScreenRecord"])

        let all = buildNodeCapabilities(cameraEnabled: true, screenEnabled: true)
        #expect(all == ["Canvas", "Camera", "ScreenRecord"])
    }

    // MARK: - BridgeInvokeRequest

    @Test("BridgeInvokeRequest decodeParams works")
    func bridgeRequest_decode() {
        let params = """
        {"url":"https://example.com","placement":{"width":800,"height":600}}
        """
        let request = BridgeInvokeRequest(id: "1", command: "canvas.present", paramsJSON: params)
        let decoded = request.decodeParams(CanvasPresentParams.self)
        #expect(decoded?.url == "https://example.com")
        #expect(decoded?.placement?.width == 800)
        #expect(decoded?.placement?.height == 600)
    }

    @Test("BridgeInvokeRequest decodeParams nil for invalid JSON")
    func bridgeRequest_decodeNil() {
        let request = BridgeInvokeRequest(id: "1", command: "test", paramsJSON: "not json")
        let decoded = request.decodeParams(CanvasPresentParams.self)
        #expect(decoded == nil)
    }

    @Test("BridgeInvokeRequest decodeParams nil for nil paramsJSON")
    func bridgeRequest_decodeNilParams() {
        let request = BridgeInvokeRequest(id: "1", command: "test")
        let decoded = request.decodeParams(CanvasPresentParams.self)
        #expect(decoded == nil)
    }

    // MARK: - BridgeInvokeResponse

    @Test("BridgeInvokeResponse success factory")
    func bridgeResponse_success() {
        let response = BridgeInvokeResponse.success(id: "42")
        #expect(response.id == "42")
        #expect(response.ok == true)
        #expect(response.error == nil)
    }

    @Test("BridgeInvokeResponse failure factory")
    func bridgeResponse_failure() {
        let response = BridgeInvokeResponse.failure(id: "42", code: .permissionDenied, message: "No access")
        #expect(response.id == "42")
        #expect(response.ok == false)
        #expect(response.error?.code == .permissionDenied)
        #expect(response.error?.message == "No access")
    }

    @Test("BridgeInvokeResponse success with payload")
    func bridgeResponse_successPayload() {
        struct TestPayload: Codable { let value: String }
        let response = BridgeInvokeResponse.success(id: "1", payload: TestPayload(value: "hello"))
        #expect(response.ok == true)
        #expect(response.payloadJSON?.contains("hello") == true)
    }

    // MARK: - BridgeHello

    @Test("BridgeHello encodes correctly")
    func bridgeHello() throws {
        let hello = BridgeHello(
            nodeId: "test-node",
            displayName: "Test",
            caps: ["Canvas", "Camera"],
            commands: ["canvas.present", "camera.snap"]
        )
        let data = try JSONEncoder().encode(hello)
        let decoded = try JSONDecoder().decode(BridgeHello.self, from: data)
        #expect(decoded.type == "hello")
        #expect(decoded.nodeId == "test-node")
        #expect(decoded.displayName == "Test")
        #expect(decoded.caps == ["Canvas", "Camera"])
        #expect(decoded.commands?.count == 2)
    }

    // MARK: - Codable Models

    @Test("CameraSnapParams encodes/decodes")
    func cameraSnapParams() throws {
        let params = CameraSnapParams(facing: .front, maxWidth: 1920, quality: 0.9, delayMs: 500)
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(CameraSnapParams.self, from: data)
        #expect(decoded.facing == .front)
        #expect(decoded.maxWidth == 1920)
        #expect(decoded.quality == 0.9)
        #expect(decoded.delayMs == 500)
    }

    @Test("ScreenRecordParams encodes/decodes")
    func screenRecordParams() throws {
        let params = ScreenRecordParams(screenIndex: 0, durationMs: 5000, fps: 30, includeAudio: true)
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(ScreenRecordParams.self, from: data)
        #expect(decoded.screenIndex == 0)
        #expect(decoded.durationMs == 5000)
        #expect(decoded.fps == 30)
        #expect(decoded.includeAudio == true)
    }

    @Test("CameraDeviceInfo identifiable")
    func cameraDeviceInfo() {
        let device = CameraDeviceInfo(id: "cam-1", name: "FaceTime HD", position: .front)
        #expect(device.id == "cam-1")
        #expect(device.name == "FaceTime HD")
        #expect(device.position == .front)
    }

    @Test("NodeError codable")
    func nodeError() throws {
        let error = NodeError(code: .timeout, message: "Operation timed out")
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(NodeError.self, from: data)
        #expect(decoded.code == .timeout)
        #expect(decoded.message == "Operation timed out")
    }

    @Test("CanvasSnapshotFormat codable")
    func snapshotFormat() throws {
        let png = CanvasSnapshotFormat.png
        let jpeg = CanvasSnapshotFormat.jpeg
        let pngData = try JSONEncoder().encode(png)
        let jpegData = try JSONEncoder().encode(jpeg)
        let decodedPng = try JSONDecoder().decode(CanvasSnapshotFormat.self, from: pngData)
        let decodedJpeg = try JSONDecoder().decode(CanvasSnapshotFormat.self, from: jpegData)
        #expect(decodedPng == .png)
        #expect(decodedJpeg == .jpeg)
    }
}
