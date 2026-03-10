import Foundation
import AppKit
import AVFoundation
import Logging
import McClawKit

/// Captures photos and video clips from the camera.
actor CameraCaptureService {
    static let shared = CameraCaptureService()

    private let logger = Logger(label: "ai.mcclaw.node.camera")

    /// Maximum clip duration (milliseconds).
    private static let maxClipDuration = 30_000

    // MARK: - List Devices

    /// List available camera devices.
    func listDevices() -> [CameraDeviceInfo] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        return discoverySession.devices.map { device in
            let position: CameraFacing? = switch device.position {
            case .front: .front
            case .back: .back
            default: nil
            }
            return CameraDeviceInfo(id: device.uniqueID, name: device.localizedName, position: position)
        }
    }

    // MARK: - Snap (Photo)

    /// Capture a single photo.
    func snap(params: CameraSnapParams) async throws -> (data: Data, width: Int, height: Int) {
        // Check permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            throw NodeError(code: .permissionDenied, message: "Camera access denied")
        }
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw NodeError(code: .permissionDenied, message: "Camera access not granted")
            }
        }

        // Find device
        let device = try findDevice(facing: params.facing, deviceId: params.deviceId)

        // Setup capture session
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .photo

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NodeError(code: .unavailable, message: "Cannot add camera input")
        }
        session.addInput(input)

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw NodeError(code: .unavailable, message: "Cannot add photo output")
        }
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()

        // Warm-up delay for auto-exposure/white-balance
        let delayMs = params.delayMs ?? 500
        if delayMs > 0 {
            try await Task.sleep(for: .milliseconds(delayMs))
        }

        // Capture photo
        let photoDelegate = PhotoCaptureDelegate()
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: photoDelegate)

        let imageData = try await photoDelegate.waitForPhoto()
        session.stopRunning()

        // Process image
        guard let nsImage = NSImage(data: imageData) else {
            throw NodeError(code: .internalError, message: "Failed to create image from capture data")
        }

        var finalImage = nsImage
        // Resize if maxWidth specified
        if let maxWidth = params.maxWidth, maxWidth > 0, Int(nsImage.size.width) > maxWidth {
            let scale = Double(maxWidth) / nsImage.size.width
            let newSize = NSSize(width: Double(maxWidth), height: nsImage.size.height * scale)
            let resized = NSImage(size: newSize)
            resized.lockFocus()
            nsImage.draw(in: NSRect(origin: .zero, size: newSize))
            resized.unlockFocus()
            finalImage = resized
        }

        // Encode as JPEG
        guard let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw NodeError(code: .internalError, message: "Failed to create bitmap")
        }

        let quality = params.quality ?? 0.85
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw NodeError(code: .internalError, message: "JPEG encoding failed")
        }

        return (data: jpegData, width: Int(finalImage.size.width), height: Int(finalImage.size.height))
    }

    // MARK: - Clip (Video)

    /// Record a short video clip.
    func clip(params: CameraClipParams) async throws -> (path: String, durationMs: Int, width: Int, height: Int) {
        // Check permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            throw NodeError(code: .permissionDenied, message: "Camera access denied")
        }
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw NodeError(code: .permissionDenied, message: "Camera access not granted")
            }
        }

        let device = try findDevice(facing: params.facing, deviceId: params.deviceId)
        let durationMs = min(params.durationMs ?? 5000, Self.maxClipDuration)
        let includeAudio = params.includeAudio ?? false

        // Setup capture session
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        let videoInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(videoInput) else {
            throw NodeError(code: .unavailable, message: "Cannot add camera input")
        }
        session.addInput(videoInput)

        if includeAudio {
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }
        }

        let movieOutput = AVCaptureMovieFileOutput()
        guard session.canAddOutput(movieOutput) else {
            throw NodeError(code: .unavailable, message: "Cannot add movie output")
        }
        session.addOutput(movieOutput)
        session.commitConfiguration()

        // Output file
        let outputPath = NSTemporaryDirectory() + "mcclaw-camera-clip-\(UUID().uuidString).mp4"
        let outputURL = URL(fileURLWithPath: outputPath)

        session.startRunning()

        // Warm-up
        try await Task.sleep(for: .milliseconds(300))

        // Record
        let recordDelegate = MovieRecordDelegate()
        movieOutput.maxRecordedDuration = CMTime(value: Int64(durationMs), timescale: 1000)
        movieOutput.startRecording(to: outputURL, recordingDelegate: recordDelegate)

        // Wait for recording to complete
        try await recordDelegate.waitForCompletion()
        session.stopRunning()

        let dimensions = device.activeFormat.formatDescription.dimensions
        logger.info("Camera clip saved to \(outputPath)")

        return (path: outputPath, durationMs: durationMs,
                width: Int(dimensions.width), height: Int(dimensions.height))
    }

    // MARK: - Private

    private func findDevice(facing: CameraFacing?, deviceId: String?) throws -> AVCaptureDevice {
        if let deviceId {
            guard let device = AVCaptureDevice(uniqueID: deviceId) else {
                throw NodeError(code: .invalidRequest, message: "Camera device not found: \(deviceId)")
            }
            return device
        }

        let position: AVCaptureDevice.Position = switch facing {
        case .front: .front
        case .back: .back
        case nil: .unspecified
        }

        if position != .unspecified {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: position
            )
            if let device = discovery.devices.first {
                return device
            }
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw NodeError(code: .unavailable, message: "No camera available")
        }
        return device
    }
}

// MARK: - Photo Capture Delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?

    func waitForPhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: NodeError(code: .internalError, message: "No photo data"))
            return
        }
        continuation?.resume(returning: data)
    }
}

// MARK: - Movie Record Delegate

private final class MovieRecordDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForCompletion() async throws {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}
