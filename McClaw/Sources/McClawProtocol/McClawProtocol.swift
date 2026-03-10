/// McClawProtocol - Gateway protocol models.
/// Defines the WebSocket protocol v3 message types
/// shared between McClaw and the Gateway.

import Foundation

/// Protocol version.
public let mcclawProtocolVersion = 3

/// All supported Gateway RPC methods.
public enum GatewayMethod: String, Sendable, CaseIterable {
    // Handshake
    case hello

    // Agent
    case agentSend = "agent.send"
    case agentAbort = "agent.abort"
    case agentPause = "agent.pause"
    case agentResume = "agent.resume"
    case agentStatus = "agent.status"

    // Chat
    case chatHistory = "chat.history"
    case chatSessions = "chat.sessions"
    case chatDelete = "chat.delete"

    // Health
    case healthSnapshot = "health.snapshot"
    case healthPing = "health.ping"

    // Channels
    case channelsList = "channels.list"
    case channelsStatus = "channels.status"
    case channelsLogin = "channels.login"
    case channelsLogout = "channels.logout"

    // Plugins
    case pluginsList = "plugins.list"
    case pluginsInstall = "plugins.install"
    case pluginsUninstall = "plugins.uninstall"
    case pluginsConfig = "plugins.config"

    // Cron
    case cronList = "cron.list"
    case cronCreate = "cron.create"
    case cronDelete = "cron.delete"
    case cronToggle = "cron.toggle"

    // Skills
    case skillsList = "skills.list"
    case skillsInstall = "skills.install"

    // Config
    case configGet = "config.get"
    case configSet = "config.set"

    // Presence
    case presenceList = "presence.list"

    // Node
    case nodeRegister = "node.register"
    case nodeCapabilities = "node.capabilities"

    // Canvas
    case canvasShow = "canvas.show"
    case canvasClear = "canvas.clear"
}

/// All Gateway push event types.
public enum GatewayEventType: String, Sendable {
    case agentWorking = "agent.working"
    case agentIdle = "agent.idle"
    case agentError = "agent.error"
    case chatMessage = "chat.message"
    case chatTyping = "chat.typing"
    case healthUpdate = "health.update"
    case channelMessage = "channel.message"
    case channelStatus = "channel.status"
    case cronRun = "cron.run"
    case presenceUpdate = "presence.update"
}
