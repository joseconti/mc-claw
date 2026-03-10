import SwiftUI
import Speech

/// Voice settings tab in the Settings window.
struct VoiceSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var voiceMode = VoiceModeService.shared
    @State private var recognition = SpeechRecognitionService.shared
    @State private var synthesis = SpeechSynthesisService.shared
    @State private var pushToTalk = PushToTalkService.shared
    @State private var permissionManager = PermissionManager.shared

    @State private var testTranscript: String = ""
    @State private var isTesting: Bool = false
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                microphonePermissionSection
                recognitionSection
                synthesisSection
                pushToTalkSection
                wakeWordSection
                testSection
            }
            .padding()
        }
    }

    // MARK: - Microphone Permission

    private var microphonePermissionSection: some View {
        GroupBox("Microphone") {
            HStack {
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
                Text("Microphone access is required for Voice Mode.")
                    .font(.subheadline)
                Spacer()

                let status = permissionManager.microphoneStatus
                HStack(spacing: 4) {
                    Circle()
                        .fill(status == .granted ? .green : status == .denied ? .red : .gray)
                        .frame(width: 6, height: 6)
                    Text(status.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if status != .granted {
                    Button("Request") {
                        Task { _ = await permissionManager.requestMicrophone() }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Recognition Settings

    private var recognitionSection: some View {
        GroupBox("Speech Recognition") {
            VStack(alignment: .leading, spacing: 10) {
                // Language
                HStack {
                    Text("Language")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { recognition.locale?.identifier ?? "system" },
                        set: { newValue in
                            recognition.locale = newValue == "system" ? nil : Locale(identifier: newValue)
                            saveConfig()
                        }
                    )) {
                        Text("System Default").tag("system")
                        ForEach(supportedLocales, id: \.self) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale) ?? locale)
                                .tag(locale)
                        }
                    }
                    .fixedSize()
                }

                // Silence threshold
                HStack {
                    Text("Auto-send delay")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1fs", recognition.silenceThreshold))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                Slider(value: Binding(
                    get: { recognition.silenceThreshold },
                    set: { recognition.silenceThreshold = $0 }
                ), in: 0.5...3.0, step: 0.1) {
                    Text("Silence threshold")
                } onEditingChanged: { editing in
                    if !editing { saveConfig() }
                }
                Text("Time of silence before auto-sending the message.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Synthesis Settings

    private var synthesisSection: some View {
        GroupBox("Text-to-Speech") {
            VStack(alignment: .leading, spacing: 10) {
                // Voice selection
                HStack {
                    Text("Voice")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { synthesis.selectedVoice ?? "default" },
                        set: { newValue in
                            synthesis.selectedVoice = newValue == "default" ? nil : newValue
                            saveConfig()
                        }
                    )) {
                        Text("System Default").tag("default")
                        ForEach(synthesis.availableVoices(), id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.locale))")
                                .tag(voice.identifier)
                        }
                    }
                    .frame(maxWidth: 250)

                    Button("Preview") {
                        let voice = synthesis.selectedVoice ?? NSSpeechSynthesizer.defaultVoice.rawValue
                        synthesis.previewVoice(voice)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                // Speed
                HStack {
                    Text("Speed")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(synthesis.rate)) wpm")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                Slider(value: Binding(
                    get: { synthesis.rate },
                    set: { synthesis.rate = $0 }
                ), in: 100...300, step: 10) {
                    Text("Speed")
                } onEditingChanged: { editing in
                    if !editing { saveConfig() }
                }

                // Volume
                HStack {
                    Text("Volume")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(synthesis.volume * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Slider(value: Binding(
                    get: { synthesis.volume },
                    set: { synthesis.volume = $0 }
                ), in: 0...1, step: 0.05) {
                    Text("Volume")
                } onEditingChanged: { editing in
                    if !editing { saveConfig() }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Push-to-Talk

    private var pushToTalkSection: some View {
        @Bindable var state = appState
        return GroupBox("Push-to-Talk") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable Push-to-Talk", isOn: $state.voicePushToTalkEnabled)
                    .onChange(of: appState.voicePushToTalkEnabled) { _, enabled in
                        if enabled {
                            pushToTalk.start()
                        } else {
                            pushToTalk.stop()
                        }
                        saveConfig()
                    }

                Text("Hold Right Option key to record, release to send.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if appState.voicePushToTalkEnabled {
                    HStack {
                        Text("Requires Accessibility permission")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        Spacer()
                        if permissionManager.accessibilityStatus != .granted {
                            Button("Open Settings") {
                                permissionManager.openSystemSettings(for: .accessibility)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Wake Word

    private var wakeWordSection: some View {
        @Bindable var state = appState
        return GroupBox("Wake Word") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable Wake Word Detection", isOn: $state.voiceWakeEnabled)
                    .onChange(of: appState.voiceWakeEnabled) { _, enabled in
                        if enabled {
                            VoiceWakeRuntime.shared.start(triggerWords: appState.triggerWords)
                        } else {
                            VoiceWakeRuntime.shared.stop()
                        }
                        saveConfig()
                    }

                HStack {
                    Text("Trigger phrase:")
                        .font(.subheadline)
                    TextField("hey claw", text: Binding(
                        get: { appState.triggerWords.first ?? "hey claw" },
                        set: { newValue in
                            appState.triggerWords = [newValue.lowercased()]
                            saveConfig()
                        }
                    ))
                    .mcclawTextField()
                    .frame(maxWidth: 200)
                }

                Text("Say the trigger phrase to activate Voice Mode hands-free.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Test Section

    private var testSection: some View {
        GroupBox("Test") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Say something to test speech recognition:")
                    .font(.subheadline)

                HStack {
                    if isTesting {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(.green)
                            .symbolEffect(.pulse)
                        Text(testTranscript.isEmpty ? "Listening..." : testTranscript)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(isTesting ? "Stop" : "Test Microphone") {
                        if isTesting {
                            stopTest()
                        } else {
                            startTest()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private var supportedLocales: [String] {
        let locales = SFSpeechRecognizer.supportedLocales()
        return locales.map(\.identifier).sorted()
    }

    private func startTest() {
        isTesting = true
        testTranscript = ""
        let stream = SpeechRecognitionService.shared.startListening()
        testTask = Task {
            for await event in stream {
                switch event {
                case .partialTranscript(let text):
                    testTranscript = text
                case .finalTranscript(let text):
                    testTranscript = text
                case .audioLevel, .error:
                    break
                }
            }
        }
    }

    private func stopTest() {
        testTask?.cancel()
        testTask = nil
        SpeechRecognitionService.shared.stopListening()
        isTesting = false
    }

    private func saveConfig() {
        Task { await ConfigStore.shared.saveFromState() }
    }
}
