import SwiftUI

/// Voice overlay shown inside the chat window when Voice Mode is active.
/// Displays real-time transcript, audio visualization, and state indicators.
struct VoiceOverlayView: View {
    @State private var voiceMode = VoiceModeService.shared

    var body: some View {
        VStack(spacing: 12) {
            // State indicator with waveform
            HStack(spacing: 10) {
                waveformIndicator
                stateLabel
                Spacer()
                controlButtons
            }

            // Live transcript
            if !voiceMode.currentTranscript.isEmpty {
                Text(voiceMode.currentTranscript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .liquidGlass(cornerRadius: 20)
        .animation(.easeInOut(duration: 0.2), value: voiceMode.state)
        .animation(.easeInOut(duration: 0.2), value: voiceMode.currentTranscript)
    }

    // MARK: - Waveform

    @ViewBuilder
    private var waveformIndicator: some View {
        ZStack {
            // Outer pulse
            Circle()
                .fill(stateColor.opacity(0.15))
                .frame(width: 36 + CGFloat(voiceMode.audioLevel) * 12,
                       height: 36 + CGFloat(voiceMode.audioLevel) * 12)
                .animation(.easeInOut(duration: 0.1), value: voiceMode.audioLevel)

            // Inner icon
            Image(systemName: stateIcon)
                .font(.system(size: 18))
                .foregroundStyle(stateColor)
                .symbolEffect(.pulse, isActive: voiceMode.state == .listening)
        }
        .frame(width: 48, height: 48)
    }

    // MARK: - State Label

    private var stateLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stateText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(stateColor)
            Text("Voice Mode")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 8) {
            if voiceMode.state == .speaking {
                Button {
                    voiceMode.interruptSpeaking()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Skip speech")
            }

            Button {
                voiceMode.deactivate()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Turn off Voice Mode")
        }
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch voiceMode.state {
        case .off: .gray
        case .listening: .green
        case .speaking: .blue
        case .processing: .orange
        }
    }

    private var stateIcon: String {
        switch voiceMode.state {
        case .off: "mic.slash"
        case .listening: "waveform.circle.fill"
        case .speaking: "speaker.wave.2.fill"
        case .processing: "ellipsis.circle.fill"
        }
    }

    private var stateText: String {
        switch voiceMode.state {
        case .off: "Off"
        case .listening: "Listening..."
        case .speaking: "Speaking..."
        case .processing: "Processing..."
        }
    }
}
