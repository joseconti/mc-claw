import Foundation
import ScreenCaptureKit
import AVFoundation
import Logging
import McClawKit

/// Records the screen using ScreenCaptureKit.
@MainActor
final class ScreenRecordService {
    static let shared = ScreenRecordService()

    private let logger = Logger(label: "ai.mcclaw.node.screen")

    /// Maximum recording duration (seconds).
    private static let maxDuration: TimeInterval = 60

    /// Maximum FPS.
    private static let maxFPS: Double = 30

    private init() {}

    /// Record the screen and return the path to the MP4 file.
    func record(params: ScreenRecordParams) async throws -> (path: String, durationMs: Int) {
        // Check permission
        do {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw NodeError(code: .permissionDenied, message: "Screen recording permission denied")
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let displays = content.displays

        let screenIndex = params.screenIndex ?? 0
        guard screenIndex >= 0, screenIndex < displays.count else {
            throw NodeError(code: .invalidRequest, message: "Screen index \(screenIndex) out of range (0..\(displays.count - 1))")
        }

        let display = displays[screenIndex]
        let durationMs = min(params.durationMs ?? 5000, Int(Self.maxDuration * 1000))
        let fps = min(params.fps ?? 10, Self.maxFPS)
        let includeAudio = params.includeAudio ?? false

        // Configure stream
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = Int(display.width)
        streamConfig.height = Int(display.height)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        streamConfig.showsCursor = true
        streamConfig.capturesAudio = includeAudio

        // Output file
        let outputPath = NSTemporaryDirectory() + "mcclaw-screen-record-\(UUID().uuidString).mp4"
        let outputURL = URL(fileURLWithPath: outputPath)

        // Setup AVAssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(display.width),
            AVVideoHeightKey: Int(display.height),
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
            ]
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            ai.expectsMediaDataInRealTime = true
            writer.add(ai)
            audioInput = ai
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Record using SCStream
        let delegate = ScreenRecordDelegate(videoInput: videoInput, audioInput: audioInput)
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)

        try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: DispatchQueue(label: "ai.mcclaw.screen.video"))
        if includeAudio {
            try stream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: DispatchQueue(label: "ai.mcclaw.screen.audio"))
        }

        try await stream.startCapture()
        logger.info("Screen recording started (duration: \(durationMs)ms, fps: \(fps))")

        // Wait for duration
        try await Task.sleep(for: .milliseconds(durationMs))

        // Stop
        try await stream.stopCapture()
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()

        logger.info("Screen recording saved to \(outputPath)")
        return (path: outputPath, durationMs: durationMs)
    }
}

/// Delegate that writes SCStream samples to AVAssetWriter inputs.
private final class ScreenRecordDelegate: NSObject, SCStreamOutput, @unchecked Sendable {
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput?
    private var hasStarted = false

    init(videoInput: AVAssetWriterInput, audioInput: AVAssetWriterInput?) {
        self.videoInput = videoInput
        self.audioInput = audioInput
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio:
            if let audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        @unknown default:
            break
        }
    }
}
