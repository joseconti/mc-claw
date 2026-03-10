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

    // MARK: - App State

    /// Whether the agent is paused (won't respond to incoming messages)
    var isPaused: Bool = false

    /// Whether the agent is currently processing a request
    var isWorking: Bool = false

    // MARK: - Onboarding

    /// Whether the user has completed the first-run wizard
    var hasCompletedOnboarding: Bool = false

    /// Whether to show the onboarding wizard
    var showOnboarding: Bool = false

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

    /// Show debug pane in settings
    var debugPaneEnabled: Bool = false

    /// Enable file logging to ~/.mcclaw/logs/mcclaw.log
    var fileLoggingEnabled: Bool = false

    /// Chat font size (points). Default 16 for comfortable reading.
    var chatFontSize: CGFloat = 16

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
