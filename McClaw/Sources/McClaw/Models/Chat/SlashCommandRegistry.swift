import Foundation

/// Metadata for a slash command, used by the autocomplete popup.
struct SlashCommandDefinition: Identifiable {
    let id: String
    let command: String
    let descriptionKey: String
    let argumentHint: String?
    let icon: String
    /// Which CLIs support this command (nil = McClaw handles it natively).
    let cliHint: String?

    init(id: String, command: String, descriptionKey: String, argumentHint: String? = nil, icon: String, cliHint: String? = nil) {
        self.id = id
        self.command = command
        self.descriptionKey = descriptionKey
        self.argumentHint = argumentHint
        self.icon = icon
        self.cliHint = cliHint
    }

    var localizedDescription: String {
        String(localized: String.LocalizationValue(descriptionKey), bundle: .module)
    }

    /// True if this command is handled by McClaw directly.
    var isNative: Bool { cliHint == nil }
}

/// Registry of all available slash commands with filtering support.
enum SlashCommandRegistry {

    // MARK: - McClaw native commands

    static let nativeCommands: [SlashCommandDefinition] = [
        .init(id: "/help",     command: "/help",     descriptionKey: "cmd.help.desc",     icon: "questionmark.circle"),
        .init(id: "/status",   command: "/status",   descriptionKey: "cmd.status.desc",   icon: "info.circle"),
        .init(id: "/new",      command: "/new",      descriptionKey: "cmd.new.desc",      icon: "plus.message"),
        .init(id: "/reset",    command: "/reset",    descriptionKey: "cmd.reset.desc",     icon: "trash"),
        .init(id: "/compact",  command: "/compact",  descriptionKey: "cmd.compact.desc",  icon: "rectangle.compress.vertical"),
        .init(id: "/think",    command: "/think",    descriptionKey: "cmd.think.desc",    argumentHint: "<prompt>", icon: "brain"),
        .init(id: "/model",    command: "/model",    descriptionKey: "cmd.model.desc",    argumentHint: "[name]",   icon: "cpu"),
        .init(id: "/provider", command: "/provider", descriptionKey: "cmd.provider.desc", argumentHint: "[name]",   icon: "cpu"),
        .init(id: "/session",  command: "/session",  descriptionKey: "cmd.session.desc",  argumentHint: "[name]",   icon: "tray.2"),
        .init(id: "/fetch",    command: "/fetch",    descriptionKey: "cmd.fetch.desc",    argumentHint: "connector.action", icon: "arrow.down.doc"),
        .init(id: "/install",  command: "/install",  descriptionKey: "cmd.install.desc",  argumentHint: "<prompt>", icon: "square.and.arrow.down"),
        .init(id: "/copy",     command: "/copy",     descriptionKey: "cmd.copy.desc",     icon: "doc.on.doc"),
        .init(id: "/diff",     command: "/diff",     descriptionKey: "cmd.diff.desc",     icon: "plus.forwardslash.minus"),
        .init(id: "/plan",     command: "/plan",     descriptionKey: "cmd.plan.desc",     icon: "binoculars"),
        .init(id: "/export",   command: "/export",   descriptionKey: "cmd.export.desc",   icon: "square.and.arrow.up"),
    ]

    // MARK: - CLI pass-through commands (delegated to active CLI)

    static let cliCommands: [SlashCommandDefinition] = [
        .init(id: "cli:/init",       command: "/init",       descriptionKey: "cmd.init.desc",       icon: "doc.badge.plus",              cliHint: "Claude · Gemini · Codex"),
        .init(id: "cli:/memory",     command: "/memory",     descriptionKey: "cmd.memory.desc",     icon: "brain.head.profile",          cliHint: "Claude · Gemini"),
        .init(id: "cli:/mcp",        command: "/mcp",        descriptionKey: "cmd.mcp.desc",        icon: "server.rack",                 cliHint: "Claude · Gemini · Codex"),
        .init(id: "cli:/rewind",     command: "/rewind",     descriptionKey: "cmd.rewind.desc",     icon: "arrow.counterclockwise",      cliHint: "Claude · Gemini"),
        .init(id: "cli:/hooks",      command: "/hooks",      descriptionKey: "cmd.hooks.desc",      icon: "link",                        cliHint: "Claude · Gemini"),
        .init(id: "cli:/skills",     command: "/skills",     descriptionKey: "cmd.skills.desc",     icon: "sparkles",                    cliHint: "Claude · Gemini"),
        .init(id: "cli:/theme",      command: "/theme",      descriptionKey: "cmd.theme.desc",      icon: "paintpalette",                cliHint: "Claude · Gemini"),
        .init(id: "cli:/vim",        command: "/vim",        descriptionKey: "cmd.vim.desc",        icon: "keyboard",                    cliHint: "Claude · Gemini"),
        .init(id: "cli:/permissions",command: "/permissions", descriptionKey: "cmd.permissions.desc",icon: "lock.shield",                 cliHint: "Claude · Gemini · Codex"),
        .init(id: "cli:/resume",     command: "/resume",     descriptionKey: "cmd.resume.desc",     icon: "play.circle",                 cliHint: "Claude · Gemini · Codex"),
        .init(id: "cli:/fork",       command: "/fork",       descriptionKey: "cmd.fork.desc",       icon: "arrow.triangle.branch",       cliHint: "Claude · Codex"),
        .init(id: "cli:/fast",       command: "/fast",       descriptionKey: "cmd.fast.desc",       icon: "hare",                        cliHint: "Claude"),
        .init(id: "cli:/context",    command: "/context",    descriptionKey: "cmd.context.desc",    icon: "chart.bar",                   cliHint: "Claude"),
        .init(id: "cli:/btw",        command: "/btw",        descriptionKey: "cmd.btw.desc",        argumentHint: "<question>",          icon: "bubble.left", cliHint: "Claude"),
        .init(id: "cli:/doctor",     command: "/doctor",     descriptionKey: "cmd.doctor.desc",     icon: "stethoscope",                 cliHint: "Claude"),
        .init(id: "cli:/pr-comments",command: "/pr-comments",descriptionKey: "cmd.prcomments.desc", argumentHint: "[PR]",                icon: "text.bubble", cliHint: "Claude"),
        .init(id: "cli:/compress",   command: "/compress",   descriptionKey: "cmd.compress.desc",   icon: "rectangle.compress.vertical", cliHint: "Gemini"),
        .init(id: "cli:/extensions", command: "/extensions", descriptionKey: "cmd.extensions.desc", icon: "puzzlepiece.extension",       cliHint: "Gemini"),
        .init(id: "cli:/agent",      command: "/agent",      descriptionKey: "cmd.agent.desc",      icon: "person.2",                    cliHint: "Codex"),
        .init(id: "cli:/mention",    command: "/mention",    descriptionKey: "cmd.mention.desc",    argumentHint: "<file>",              icon: "at",          cliHint: "Codex"),
    ]

    /// All commands: native first, then CLI pass-through.
    static let all: [SlashCommandDefinition] = nativeCommands + cliCommands

    /// Filter commands by prefix. Returns all if query is just "/".
    static func filter(query: String) -> [SlashCommandDefinition] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.hasPrefix("/") else { return [] }
        if q == "/" { return all }
        return all.filter { $0.command.hasPrefix(q) }
    }
}
