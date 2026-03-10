import Foundation

/// Protocol for native channel implementations.
/// Each channel (Telegram, Slack, Discord) implements this to provide
/// persistent background connections directly from McClaw.
protocol NativeChannel: Actor {
    /// The channel definition ID (e.g. "telegram").
    var channelId: String { get }

    /// Current connection state.
    var state: NativeChannelState { get }

    /// Connection stats.
    var stats: NativeChannelStats { get }

    /// Bot info (name, username, etc.) — available after connecting.
    var botDisplayName: String? { get }

    /// Start the persistent connection.
    func start(config: NativeChannelConfig) async

    /// Stop the connection gracefully.
    func stop() async

    /// Set the callback for incoming messages.
    func setOnMessage(_ handler: @escaping @Sendable (NativeChannelMessage) async -> String?) async
}
