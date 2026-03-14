import Foundation
import Logging

/// Manages persistent configuration files in ~/.mcclaw/
actor ConfigStore {
    static let shared = ConfigStore()

    private let logger = Logger(label: "ai.mcclaw.config")

    /// Base configuration directory.
    var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
    }

    /// Load the main configuration file.
    func loadConfig() async -> McClawConfig? {
        let configFile = configDirectory.appendingPathComponent("mcclaw.json")
        guard let data = try? Data(contentsOf: configFile) else {
            logger.info("No config file found, using defaults")
            return nil
        }

        do {
            return try JSONDecoder().decode(McClawConfig.self, from: data)
        } catch {
            logger.error("Config parse error: \(error)")
            return nil
        }
    }

    /// Save the main configuration file.
    func saveConfig(_ config: McClawConfig) async throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configFile = configDirectory.appendingPathComponent("mcclaw.json")
        let data = try JSONEncoder().encode(config)
        try data.write(to: configFile)
        logger.info("Config saved")
    }

    /// Ensure all required directories exist.
    func ensureDirectories() async throws {
        let dirs = [
            configDirectory,
            configDirectory.appendingPathComponent("credentials"),
            configDirectory.appendingPathComponent("sessions"),
            configDirectory.appendingPathComponent("workspace"),
            configDirectory.appendingPathComponent("workspace/skills"),
            configDirectory.appendingPathComponent("connectors"),
            configDirectory.appendingPathComponent("skills"),
            configDirectory.appendingPathComponent("git"),
        ]

        for dir in dirs {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Apply saved config to AppState.
    @MainActor
    func applyToState(_ config: McClawConfig) {
        let state = AppState.shared
        state.currentCLIIdentifier = config.defaultCLI
        state.connectionMode = config.connectionMode
        state.gatewayPort = config.gatewayPort
        state.remoteTransport = config.remoteTransport
        state.remoteTarget = config.remoteTarget
        state.remoteUrl = config.remoteUrl
        state.remoteIdentity = config.remoteIdentity
        state.voiceWakeEnabled = config.voiceEnabled
        state.canvasEnabled = config.canvasEnabled
        state.cameraEnabled = config.cameraEnabled
        state.screenEnabled = config.screenEnabled
        state.hasCompletedOnboarding = config.hasCompletedOnboarding
        state.userName = config.userName
        state.userEmail = config.userEmail
        state.userDescription = config.userDescription

        // Always start with a fresh chat — user can pick old sessions from the sidebar.
        // We still save lastSessionId to config for potential future use.

        // Voice settings
        state.voicePushToTalkEnabled = config.pushToTalkEnabled
        state.selectedVoice = config.selectedVoice
        state.speechRate = config.speechRate
        state.speechVolume = config.speechVolume
        state.silenceThreshold = config.silenceThreshold
        state.recognitionLocale = config.recognitionLocale
        if let triggerWords = config.triggerWords, !triggerWords.isEmpty {
            state.triggerWords = triggerWords
        }

        // Apply voice config to services
        SpeechSynthesisService.shared.selectedVoice = config.selectedVoice
        SpeechSynthesisService.shared.rate = config.speechRate
        SpeechSynthesisService.shared.volume = config.speechVolume
        SpeechRecognitionService.shared.silenceThreshold = config.silenceThreshold
        if let locale = config.recognitionLocale {
            SpeechRecognitionService.shared.locale = Locale(identifier: locale)
        }

        // Apply node mode settings
        NodeMode.shared.cameraEnabled = config.cameraEnabled
        NodeMode.shared.screenEnabled = config.screenEnabled

        // UI preferences
        state.keepInMenuBar = config.keepInMenuBar
        if let fontSize = config.chatFontSize {
            state.chatFontSize = fontSize
        }
        if let colorScheme = config.appColorScheme {
            state.appColorScheme = colorScheme
        }
        if let fontFamily = config.chatFontFamily {
            state.chatFontFamily = fontFamily
        }

        // Theme
        if let preset = config.themePreset {
            ThemeManager.shared.selectedPreset = preset
        }
        if let custom = config.customThemeColors {
            ThemeManager.shared.customColors = custom
        }

        // Apply file logging
        state.fileLoggingEnabled = config.fileLoggingEnabled
        DiagnosticsFileLogHandler.isEnabled = config.fileLoggingEnabled

        // BitNet settings
        state.showExperimentalProviders = config.showExperimentalProviders
        state.bitnetEnabled = config.bitnetEnabled
        state.bitnetDefaultModel = config.bitnetDefaultModel
        state.bitnetThreads = config.bitnetThreads
        state.bitnetContextSize = config.bitnetContextSize
        state.bitnetMaxTokens = config.bitnetMaxTokens
        state.bitnetTemperature = config.bitnetTemperature
        state.bitnetServerPort = config.bitnetServerPort
        state.bitnetAlwaysOn = config.bitnetAlwaysOn

        // Ollama settings
        state.ollamaAlwaysOn = config.ollamaAlwaysOn
        state.ollamaServerPort = config.ollamaServerPort

        // DashScope settings
        state.dashscopeRegion = config.dashscopeRegion
        state.dashscopeAPIKeyStored = config.dashscopeAPIKeyStored

        // Hidden providers
        state.hiddenProviders = config.hiddenProviders

        // Git Integration
        state.gitSectionEnabled = config.gitSectionEnabled

        // Project Memory
        state.memoryProviderId = config.memoryProviderId
        state.projectMemoryAutoUpdate = config.projectMemoryAutoUpdate

        // Model selection
        if let models = config.defaultModels {
            state.defaultModels = models
        }

        // Apply security mode
        ExecApprovals.shared.securityMode = config.execMode
        // Load allowlist/denylist from separate file
        ExecApprovals.shared.loadFromFile()
    }

    /// Save current AppState to config file.
    @MainActor
    func saveFromState() async {
        let state = AppState.shared
        let config = McClawConfig(
            defaultCLI: state.currentCLIIdentifier,
            gatewayPort: state.gatewayPort,
            connectionMode: state.connectionMode,
            remoteTransport: state.remoteTransport,
            remoteTarget: state.remoteTarget,
            remoteUrl: state.remoteUrl,
            remoteIdentity: state.remoteIdentity,
            voiceEnabled: state.voiceWakeEnabled,
            canvasEnabled: state.canvasEnabled,
            cameraEnabled: state.cameraEnabled,
            screenEnabled: state.screenEnabled,
            execMode: ExecApprovals.shared.securityMode,
            hasCompletedOnboarding: state.hasCompletedOnboarding,
            pushToTalkEnabled: state.voicePushToTalkEnabled,
            selectedVoice: state.selectedVoice,
            speechRate: state.speechRate,
            speechVolume: state.speechVolume,
            silenceThreshold: state.silenceThreshold,
            recognitionLocale: state.recognitionLocale,
            triggerWords: state.triggerWords,
            userName: state.userName,
            userEmail: state.userEmail,
            userDescription: state.userDescription,
            keepInMenuBar: state.keepInMenuBar,
            chatFontSize: state.chatFontSize,
            appColorScheme: state.appColorScheme,
            chatFontFamily: state.chatFontFamily,
            fileLoggingEnabled: state.fileLoggingEnabled,
            showExperimentalProviders: state.showExperimentalProviders,
            bitnetEnabled: state.bitnetEnabled,
            bitnetDefaultModel: state.bitnetDefaultModel,
            bitnetThreads: state.bitnetThreads,
            bitnetContextSize: state.bitnetContextSize,
            bitnetMaxTokens: state.bitnetMaxTokens,
            bitnetTemperature: state.bitnetTemperature,
            bitnetServerPort: state.bitnetServerPort,
            bitnetAlwaysOn: state.bitnetAlwaysOn,
            ollamaAlwaysOn: state.ollamaAlwaysOn,
            ollamaServerPort: state.ollamaServerPort,
            dashscopeRegion: state.dashscopeRegion,
            dashscopeAPIKeyStored: state.dashscopeAPIKeyStored,
            hiddenProviders: state.hiddenProviders,
            gitSectionEnabled: state.gitSectionEnabled,
            memoryProviderId: state.memoryProviderId,
            projectMemoryAutoUpdate: state.projectMemoryAutoUpdate,
            defaultModels: state.defaultModels.isEmpty ? nil : state.defaultModels,
            lastSessionId: state.currentSessionId,
            themePreset: ThemeManager.shared.selectedPreset,
            customThemeColors: ThemeManager.shared.selectedPreset == .custom ? ThemeManager.shared.customColors : nil
        )
        do {
            try await saveConfig(config)
        } catch {
            logger.error("Failed to save config: \(error)")
        }
    }
}

/// Main configuration structure.
struct McClawConfig: Codable, Sendable {
    var defaultCLI: String?
    var gatewayPort: Int
    var connectionMode: ConnectionMode
    var voiceEnabled: Bool
    var canvasEnabled: Bool
    var cameraEnabled: Bool
    var screenEnabled: Bool
    var execMode: ExecSecurityMode
    var hasCompletedOnboarding: Bool

    // Remote settings
    var remoteTransport: RemoteTransport
    var remoteTarget: String?
    var remoteUrl: String?
    var remoteIdentity: String?

    // Voice settings
    var pushToTalkEnabled: Bool
    var selectedVoice: String?
    var speechRate: Float
    var speechVolume: Float
    var silenceThreshold: TimeInterval
    var recognitionLocale: String?
    var triggerWords: [String]?

    // User profile
    var userName: String?
    var userEmail: String?
    var userDescription: String?

    // UI preferences
    var keepInMenuBar: Bool
    var chatFontSize: CGFloat?
    var appColorScheme: AppColorScheme?
    var chatFontFamily: ChatFontFamily?

    // Theme
    var themePreset: ThemePresetId?
    var customThemeColors: ThemeColors?

    // Diagnostics
    var fileLoggingEnabled: Bool

    // BitNet (experimental)
    var showExperimentalProviders: Bool
    var bitnetEnabled: Bool
    var bitnetDefaultModel: String?
    var bitnetThreads: Int
    var bitnetContextSize: Int
    var bitnetMaxTokens: Int
    var bitnetTemperature: Double
    var bitnetServerPort: Int
    var bitnetAlwaysOn: Bool

    // Ollama
    var ollamaAlwaysOn: Bool
    var ollamaServerPort: Int

    // DashScope (Alibaba Cloud)
    var dashscopeRegion: String
    var dashscopeAPIKeyStored: Bool

    // Hidden Providers
    var hiddenProviders: Set<String>

    // Git Integration
    var gitSectionEnabled: Bool

    // Project Memory
    var memoryProviderId: String?
    var projectMemoryAutoUpdate: Bool

    // Model selection per provider
    var defaultModels: [String: String]?

    // Session
    var lastSessionId: String?

    init(
        defaultCLI: String? = nil,
        gatewayPort: Int = 3577,
        connectionMode: ConnectionMode = .local,
        remoteTransport: RemoteTransport = .ssh,
        remoteTarget: String? = nil,
        remoteUrl: String? = nil,
        remoteIdentity: String? = nil,
        voiceEnabled: Bool = false,
        canvasEnabled: Bool = false,
        cameraEnabled: Bool = false,
        screenEnabled: Bool = true,
        execMode: ExecSecurityMode = .ask,
        hasCompletedOnboarding: Bool = false,
        pushToTalkEnabled: Bool = false,
        selectedVoice: String? = nil,
        speechRate: Float = 180,
        speechVolume: Float = 1.0,
        silenceThreshold: TimeInterval = 1.5,
        recognitionLocale: String? = nil,
        triggerWords: [String]? = nil,
        userName: String? = nil,
        userEmail: String? = nil,
        userDescription: String? = nil,
        keepInMenuBar: Bool = false,
        chatFontSize: CGFloat? = nil,
        appColorScheme: AppColorScheme? = nil,
        chatFontFamily: ChatFontFamily? = nil,
        fileLoggingEnabled: Bool = false,
        showExperimentalProviders: Bool = false,
        bitnetEnabled: Bool = false,
        bitnetDefaultModel: String? = nil,
        bitnetThreads: Int = 4,
        bitnetContextSize: Int = 2048,
        bitnetMaxTokens: Int = 2048,
        bitnetTemperature: Double = 0.7,
        bitnetServerPort: Int = 8921,
        bitnetAlwaysOn: Bool = true,
        ollamaAlwaysOn: Bool = false,
        ollamaServerPort: Int = 11434,
        dashscopeRegion: String = "international",
        dashscopeAPIKeyStored: Bool = false,
        hiddenProviders: Set<String> = ["dashscope"],
        gitSectionEnabled: Bool = false,
        memoryProviderId: String? = nil,
        projectMemoryAutoUpdate: Bool = true,
        defaultModels: [String: String]? = nil,
        lastSessionId: String? = nil,
        themePreset: ThemePresetId? = nil,
        customThemeColors: ThemeColors? = nil
    ) {
        self.defaultCLI = defaultCLI
        self.gatewayPort = gatewayPort
        self.connectionMode = connectionMode
        self.remoteTransport = remoteTransport
        self.remoteTarget = remoteTarget
        self.remoteUrl = remoteUrl
        self.remoteIdentity = remoteIdentity
        self.voiceEnabled = voiceEnabled
        self.canvasEnabled = canvasEnabled
        self.cameraEnabled = cameraEnabled
        self.screenEnabled = screenEnabled
        self.execMode = execMode
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.pushToTalkEnabled = pushToTalkEnabled
        self.selectedVoice = selectedVoice
        self.speechRate = speechRate
        self.speechVolume = speechVolume
        self.silenceThreshold = silenceThreshold
        self.recognitionLocale = recognitionLocale
        self.triggerWords = triggerWords
        self.userName = userName
        self.userEmail = userEmail
        self.userDescription = userDescription
        self.keepInMenuBar = keepInMenuBar
        self.chatFontSize = chatFontSize
        self.appColorScheme = appColorScheme
        self.chatFontFamily = chatFontFamily
        self.fileLoggingEnabled = fileLoggingEnabled
        self.showExperimentalProviders = showExperimentalProviders
        self.bitnetEnabled = bitnetEnabled
        self.bitnetDefaultModel = bitnetDefaultModel
        self.bitnetThreads = bitnetThreads
        self.bitnetContextSize = bitnetContextSize
        self.bitnetMaxTokens = bitnetMaxTokens
        self.bitnetTemperature = bitnetTemperature
        self.bitnetServerPort = bitnetServerPort
        self.bitnetAlwaysOn = bitnetAlwaysOn
        self.ollamaAlwaysOn = ollamaAlwaysOn
        self.ollamaServerPort = ollamaServerPort
        self.dashscopeRegion = dashscopeRegion
        self.dashscopeAPIKeyStored = dashscopeAPIKeyStored
        self.hiddenProviders = hiddenProviders
        self.gitSectionEnabled = gitSectionEnabled
        self.memoryProviderId = memoryProviderId
        self.projectMemoryAutoUpdate = projectMemoryAutoUpdate
        self.defaultModels = defaultModels
        self.lastSessionId = lastSessionId
        self.themePreset = themePreset
        self.customThemeColors = customThemeColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultCLI = try container.decodeIfPresent(String.self, forKey: .defaultCLI)
        gatewayPort = try container.decode(Int.self, forKey: .gatewayPort)
        connectionMode = try container.decode(ConnectionMode.self, forKey: .connectionMode)
        voiceEnabled = try container.decode(Bool.self, forKey: .voiceEnabled)
        canvasEnabled = try container.decode(Bool.self, forKey: .canvasEnabled)
        cameraEnabled = try container.decode(Bool.self, forKey: .cameraEnabled)
        screenEnabled = try container.decode(Bool.self, forKey: .screenEnabled)
        execMode = try container.decode(ExecSecurityMode.self, forKey: .execMode)
        hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
        remoteTransport = try container.decode(RemoteTransport.self, forKey: .remoteTransport)
        remoteTarget = try container.decodeIfPresent(String.self, forKey: .remoteTarget)
        remoteUrl = try container.decodeIfPresent(String.self, forKey: .remoteUrl)
        remoteIdentity = try container.decodeIfPresent(String.self, forKey: .remoteIdentity)
        pushToTalkEnabled = try container.decode(Bool.self, forKey: .pushToTalkEnabled)
        selectedVoice = try container.decodeIfPresent(String.self, forKey: .selectedVoice)
        speechRate = try container.decode(Float.self, forKey: .speechRate)
        speechVolume = try container.decode(Float.self, forKey: .speechVolume)
        silenceThreshold = try container.decode(TimeInterval.self, forKey: .silenceThreshold)
        recognitionLocale = try container.decodeIfPresent(String.self, forKey: .recognitionLocale)
        triggerWords = try container.decodeIfPresent([String].self, forKey: .triggerWords)
        userName = try container.decodeIfPresent(String.self, forKey: .userName)
        userEmail = try container.decodeIfPresent(String.self, forKey: .userEmail)
        userDescription = try container.decodeIfPresent(String.self, forKey: .userDescription)
        keepInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .keepInMenuBar) ?? false
        chatFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .chatFontSize)
        appColorScheme = try container.decodeIfPresent(AppColorScheme.self, forKey: .appColorScheme)
        chatFontFamily = try container.decodeIfPresent(ChatFontFamily.self, forKey: .chatFontFamily)
        fileLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .fileLoggingEnabled) ?? false
        showExperimentalProviders = try container.decodeIfPresent(Bool.self, forKey: .showExperimentalProviders) ?? false
        bitnetEnabled = try container.decodeIfPresent(Bool.self, forKey: .bitnetEnabled) ?? false
        bitnetDefaultModel = try container.decodeIfPresent(String.self, forKey: .bitnetDefaultModel)
        bitnetThreads = try container.decodeIfPresent(Int.self, forKey: .bitnetThreads) ?? 4
        bitnetContextSize = try container.decodeIfPresent(Int.self, forKey: .bitnetContextSize) ?? 2048
        bitnetMaxTokens = try container.decodeIfPresent(Int.self, forKey: .bitnetMaxTokens) ?? 2048
        bitnetTemperature = try container.decodeIfPresent(Double.self, forKey: .bitnetTemperature) ?? 0.7
        bitnetServerPort = try container.decodeIfPresent(Int.self, forKey: .bitnetServerPort) ?? 8921
        bitnetAlwaysOn = try container.decodeIfPresent(Bool.self, forKey: .bitnetAlwaysOn) ?? true
        ollamaAlwaysOn = try container.decodeIfPresent(Bool.self, forKey: .ollamaAlwaysOn) ?? false
        ollamaServerPort = try container.decodeIfPresent(Int.self, forKey: .ollamaServerPort) ?? 11434
        dashscopeRegion = try container.decodeIfPresent(String.self, forKey: .dashscopeRegion) ?? "international"
        dashscopeAPIKeyStored = try container.decodeIfPresent(Bool.self, forKey: .dashscopeAPIKeyStored) ?? false
        hiddenProviders = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenProviders) ?? ["dashscope"]
        gitSectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .gitSectionEnabled) ?? false
        memoryProviderId = try container.decodeIfPresent(String.self, forKey: .memoryProviderId)
        projectMemoryAutoUpdate = try container.decodeIfPresent(Bool.self, forKey: .projectMemoryAutoUpdate) ?? true
        defaultModels = try container.decodeIfPresent([String: String].self, forKey: .defaultModels)
        lastSessionId = try container.decodeIfPresent(String.self, forKey: .lastSessionId)
        themePreset = try container.decodeIfPresent(ThemePresetId.self, forKey: .themePreset)
        customThemeColors = try container.decodeIfPresent(ThemeColors.self, forKey: .customThemeColors)
    }
}
