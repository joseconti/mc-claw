import AppKit
import SwiftUI

/// Central application state. Singleton, observable, main-actor isolated.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    // MARK: - Connection

    /// Current connection mode to Gateway
    var connectionMode: ConnectionMode = .unconfigured

    /// Remote transport type (when using remote Gateway)
    var remoteTransport: RemoteTransport = .ssh

    /// Remote connection target
    var remoteTarget: String?
    var remoteUrl: String?
    var remoteIdentity: String?

    // MARK: - CLI Bridge

    /// All detected CLI providers on the system
    var availableCLIs: [CLIProviderInfo] = []

    /// Identifier of the currently selected CLI
    var currentCLIIdentifier: String?

    /// Returns the currently selected CLI info
    var currentCLI: CLIProviderInfo? {
        availableCLIs.first { $0.id == currentCLIIdentifier }
    }

    /// AI provider CLIs only (excludes tool CLIs like agent-browser).
    /// Experimental providers (e.g. BitNet) only shown when toggle is enabled.
    var installedAIProviders: [CLIProviderInfo] {
        availableCLIs.filter { cli in
            cli.isInstalled && !cli.isToolCLI && (!cli.isExperimental || showExperimentalProviders)
        }
    }

    // MARK: - App State

    /// Whether the agent is paused (won't respond to incoming messages)
    var isPaused: Bool = false

    /// Whether the agent is currently processing a request
    var isWorking: Bool = false

    /// Whether Plan Mode is active for the current session (read-only analysis).
    /// Resets on new chat. Not persisted to disk.
    var planModeActive: Bool = false

    /// Path to the plan file currently displayed in the right-side panel.
    /// Setting this opens the panel; nil closes it.
    var openPlanFilePath: String?

    // MARK: - Onboarding

    /// Whether the user has completed the first-run wizard
    var hasCompletedOnboarding: Bool = false

    /// Whether to show the onboarding wizard
    var showOnboarding: Bool = false

    /// Whether to navigate to settings in the main window (triggered by Cmd+,)
    var showSettingsInMainWindow: Bool = false

    /// Section to navigate to when the chat window opens (set by floating panel or deep links).
    var pendingNavigationSection: SidebarSection?

    /// Settings tab to open when navigating to settings (e.g., from Git empty state → Connectors).
    var pendingSettingsTab: String?

    /// Project ID to create a new chat in (set by floating panel "New Chat in Project" action).
    var pendingProjectIdForNewChat: String?

    // MARK: - Voice

    /// Wake-word detection enabled
    var voiceWakeEnabled: Bool = false

    /// Push-to-talk enabled
    var voicePushToTalkEnabled: Bool = false

    /// Continuous talk mode enabled
    var talkModeEnabled: Bool = false

    /// Wake-word trigger phrases
    var triggerWords: [String] = ["hey claw"]

    /// Selected TTS voice identifier
    var selectedVoice: String?

    /// TTS speech rate (words per minute)
    var speechRate: Float = 180

    /// TTS volume (0...1)
    var speechVolume: Float = 1.0

    /// Silence threshold for auto-send (seconds)
    var silenceThreshold: TimeInterval = 1.5

    /// Recognition language locale identifier (nil = system)
    var recognitionLocale: String?

    // MARK: - User Profile

    /// User display name
    var userName: String?

    /// User email (for Gravatar avatar)
    var userEmail: String?

    /// Short description of the user's work and goals
    var userDescription: String?

    /// Cached user avatar from Gravatar
    var userAvatarImage: NSImage?

    // MARK: - UI Preferences

    /// Launch McClaw at login
    var launchAtLogin: Bool = false

    /// Show dock icon (vs menu bar only)
    var showDockIcon: Bool = false

    /// Keep app running in menu bar when windows are closed
    var keepInMenuBar: Bool = false

    /// Enable menu bar icon animations
    var iconAnimationsEnabled: Bool = true

    /// Prevent Mac from sleeping while McClaw is running
    var preventSleepEnabled: Bool = false

    /// Show debug pane in settings
    var debugPaneEnabled: Bool = false

    /// Enable file logging to ~/.mcclaw/logs/mcclaw.log
    var fileLoggingEnabled: Bool = false

    /// Chat font size (points). Default 16 for comfortable reading.
    var chatFontSize: CGFloat = 16

    /// App color scheme (light, dark, auto)
    var appColorScheme: AppColorScheme = .auto

    /// Chat font family
    var chatFontFamily: ChatFontFamily = .default

    // MARK: - Model Selection

    /// Default model per CLI provider. Key = provider ID (e.g. "claude"), value = model ID.
    var defaultModels: [String: String] = [:]

    /// Model override for the current chat message. Reset after each send.
    var chatModelOverride: String?

    /// Resolved model ID for the current provider (override → default → nil).
    var resolvedModelForCurrentProvider: String? {
        guard let pid = currentCLIIdentifier else { return nil }
        return chatModelOverride ?? defaultModels[pid]
    }

    // MARK: - Project Memory

    /// AI provider used to update project memory files. Nil = disabled.
    var memoryProviderId: String?
    /// Whether to auto-update memory after each conversation in a project.
    var projectMemoryAutoUpdate: Bool = true

    // MARK: - BitNet (Experimental)

    /// BitNet provider enabled
    var bitnetEnabled: Bool = false
    /// Default BitNet model ID
    var bitnetDefaultModel: String?
    /// Number of threads for inference
    var bitnetThreads: Int = 4
    /// Context size in tokens
    var bitnetContextSize: Int = 2048
    /// Max tokens to generate
    var bitnetMaxTokens: Int = 2048
    /// Temperature for generation
    var bitnetTemperature: Double = 0.7
    /// REST server port
    var bitnetServerPort: Int = 8921
    /// Server mode: always running or on-demand
    var bitnetAlwaysOn: Bool = true
    /// Show experimental providers in UI
    var showExperimentalProviders: Bool = false

    // MARK: - Ollama Settings

    /// Server mode: always running or start on-demand
    var ollamaAlwaysOn: Bool = false
    /// Ollama REST server port
    var ollamaServerPort: Int = 11434

    // MARK: - DashScope Settings

    /// DashScope API region (international or usVirginia)
    var dashscopeRegion: String = "international"
    /// Whether an API key is stored in Keychain (flag only, not the key itself)
    var dashscopeAPIKeyStored: Bool = false

    // MARK: - Hidden Providers

    /// Cloud provider IDs hidden from sidebar (not yet activated by the user)
    var hiddenProviders: Set<String> = ["dashscope"]

    // MARK: - Adaptive Learning

    /// Whether adaptive learning (signal detection + preference enrichment) is active.
    var adaptiveLearningEnabled: Bool = true

    /// Whether to show learning indicators in the chat UI.
    var showLearningIndicators: Bool = true

    // MARK: - Git Integration

    /// Git section enabled in sidebar
    var gitSectionEnabled: Bool = false

    // MARK: - Canvas & Node

    /// Canvas panel enabled
    var canvasEnabled: Bool = false

    /// Camera capture enabled for Node mode
    var cameraEnabled: Bool = false

    /// Screen recording enabled for Node mode
    var screenEnabled: Bool = true

    // MARK: - Gateway

    /// Gateway port
    var gatewayPort: Int = 3577

    /// Current Gateway health status
    var gatewayStatus: GatewayStatus = .disconnected

    /// Active channels
    var activeChannels: [ChannelStatus] = []

    // MARK: - Plugins

    /// Loaded plugins from Gateway
    var loadedPlugins: [PluginInfo] = []

    // MARK: - Sessions

    /// Current active session ID
    var currentSessionId: String?

    // MARK: - Menu Bar Chat

    /// Message queued from the menu bar mini chat, to be sent when the chat window opens.
    var pendingMessage: String?

    /// Image prompt queued from the menu bar mini chat, to be sent as image generation when the chat window opens.
    var pendingImagePrompt: String?

    /// Install prompt queued from the menu bar mini chat, to be sent as agent install when the chat window opens.
    var pendingInstallPrompt: String?

    /// Text to pre-fill in the chat input bar without sending (used by quick actions).
    var prefillText: String?

    /// Closure to open the chat window, set by DeepLinkAwareChat when the Scene is available.
    @ObservationIgnored var openChatWindowAction: (() -> Void)?

    /// Closure to dismiss the floating menu bar panel.
    @ObservationIgnored var dismissMenuBarPanel: (() -> Void)?

    // MARK: - Security

    /// Whether the exec approval dialog is showing
    var showingApprovalDialog: Bool = false

    // MARK: - Init

    private init() {}
}

// MARK: - Connection Types

enum ConnectionMode: String, Codable, Sendable {
    case unconfigured
    case local
    case remote
}

enum RemoteTransport: String, Codable, Sendable {
    case ssh
    case direct
}

/// App color scheme preference.
enum AppColorScheme: String, Codable, Sendable, CaseIterable {
    case light
    case auto
    case dark

    var displayName: String {
        switch self {
        case .light: return String(localized: "Light")
        case .auto: return String(localized: "Auto")
        case .dark: return String(localized: "Dark")
        }
    }

    var swiftUIScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .auto: return nil
        case .dark: return .dark
        }
    }
}

/// Chat font family preference.
enum ChatFontFamily: String, Codable, Sendable, CaseIterable {
    case `default`
    case serif
    case mono
    case dyslexic

    var displayName: String {
        switch self {
        case .default: return String(localized: "Default")
        case .serif: return String(localized: "Serif")
        case .mono: return String(localized: "Mono")
        case .dyslexic: return String(localized: "Dyslexia")
        }
    }

    /// Returns the SwiftUI Font for the given size.
    func font(size: CGFloat) -> Font {
        switch self {
        case .default:
            return .system(size: size)
        case .serif:
            return .system(size: size, design: .serif)
        case .mono:
            return .system(size: size, design: .monospaced)
        case .dyslexic:
            // OpenDyslexic bundled font, fall back to system rounded
            if NSFont(name: "OpenDyslexic", size: size) != nil {
                return .custom("OpenDyslexic", size: size)
            }
            return .system(size: size, design: .rounded)
        }
    }

    /// Preview font for the settings card.
    var previewDesign: Font.Design {
        switch self {
        case .default: return .default
        case .serif: return .serif
        case .mono: return .monospaced
        case .dyslexic: return .rounded
        }
    }
}
