import SwiftUI
import AppKit

/// Welcome screen shown when no messages exist, styled like Claude Desktop.
/// Input bar is centered in the view (not at bottom) with quick actions below.
struct WelcomeView: View {
    let onSend: (String, [Attachment]) -> Void
    let onAbort: () -> Void
    let isWorking: Bool

    @Environment(AppState.self) private var appState
    @State private var connectorStore = ConnectorStore.shared
    @State private var expandedAction: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: .infinity)

            // Logo
            Group {
                if let url = Bundle.module.url(forResource: "mcclaw-logo", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.orange.gradient)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Spacer().frame(height: 20)

            Text(greeting)
                .font(.system(size: 32, weight: .semibold))

            Spacer().frame(height: 36)

            ChatInputBar(
                onSend: onSend,
                onAbort: onAbort,
                isWorking: isWorking
            )
            .environment(appState)

            Spacer().frame(height: 14)

            quickActions

            Spacer().frame(maxHeight: .infinity)
            Spacer().frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appState.userName?.components(separatedBy: " ").first
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = String(localized: "Good morning", bundle: .module)
        case 12..<18: timeGreeting = String(localized: "Good afternoon", bundle: .module)
        default: timeGreeting = String(localized: "Good evening", bundle: .module)
        }
        if let name = name, !name.isEmpty {
            return "\(timeGreeting), \(name)"
        }
        return timeGreeting
    }

    /// Build the list of visible quick actions: 4 base + up to 4 connected connectors.
    private var visibleActions: [QuickActionItem] {
        var items = QuickActionItem.baseActions

        // Add connected connectors (max 4, prioritized)
        let connectorActions = QuickActionItem.connectorPriority.compactMap { connectorId -> QuickActionItem? in
            guard connectorStore.instance(for: connectorId)?.isConnected == true,
                  let action = QuickActionItem.connectorActions[connectorId] else { return nil }
            return action
        }
        items += Array(connectorActions.prefix(4))

        return items
    }

    @ViewBuilder
    private var quickActions: some View {
        VStack(spacing: 10) {
            // Chips — wrap if needed using two rows
            let actions = visibleActions
            let firstRow = Array(actions.prefix(5))
            let secondRow = actions.count > 5 ? Array(actions.suffix(from: 5)) : []

            HStack(spacing: 10) {
                ForEach(firstRow) { action in
                    QuickActionChip(
                        icon: action.icon,
                        label: action.label,
                        isExpanded: expandedAction == action.id
                    ) {
                        withAnimation(.snappy(duration: 0.25)) {
                            expandedAction = expandedAction == action.id ? nil : action.id
                        }
                    }
                }
            }

            if !secondRow.isEmpty {
                HStack(spacing: 10) {
                    ForEach(secondRow) { action in
                        QuickActionChip(
                            icon: action.icon,
                            label: action.label,
                            isExpanded: expandedAction == action.id
                        ) {
                            withAnimation(.snappy(duration: 0.25)) {
                                expandedAction = expandedAction == action.id ? nil : action.id
                            }
                        }
                    }
                }
            }

            // Expanded panel
            if let actionId = expandedAction,
               let action = visibleActions.first(where: { $0.id == actionId }) {
                QuickActionPanel(action: action) { prompt in
                    withAnimation(.snappy(duration: 0.2)) {
                        expandedAction = nil
                    }
                    appState.prefillText = prompt
                } onClose: {
                    withAnimation(.snappy(duration: 0.2)) {
                        expandedAction = nil
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Quick Action Data Model

private struct QuickActionItem: Identifiable {
    let id: String
    let label: String
    let icon: String
    let options: [QuickActionOption]

    // Base actions (always visible)
    static let baseActions: [QuickActionItem] = [
        QuickActionItem(
            id: "write",
            label: String(localized: "Write", bundle: .module),
            icon: "pencil.line",
            options: [
                QuickActionOption(
                    title: String(localized: "Improve my writing style", bundle: .module),
                    prompt: "I'd like to improve my writing style. If you need more context from me, ask me 1 or 2 key questions right away."
                ),
                QuickActionOption(
                    title: String(localized: "Write something creative based on mood", bundle: .module),
                    prompt: "Could you create something that reads differently based on the reader's mood? If you need more information from me, ask me 1 or 2 questions."
                ),
                QuickActionOption(
                    title: String(localized: "Create interview questions", bundle: .module),
                    prompt: "Help me create interview questions. If you need more details about the role or context, please ask."
                ),
                QuickActionOption(
                    title: String(localized: "Write product descriptions", bundle: .module),
                    prompt: "Help me write product descriptions. If you need more information about the product, ask me a couple of questions first."
                ),
                QuickActionOption(
                    title: String(localized: "Develop educational content", bundle: .module),
                    prompt: "Help me develop educational content. If you need more context about the topic or audience, please ask."
                ),
            ]
        ),
        QuickActionItem(
            id: "learn",
            label: String(localized: "Learn", bundle: .module),
            icon: "book",
            options: [
                QuickActionOption(
                    title: String(localized: "Explain a complex concept simply", bundle: .module),
                    prompt: "I want to understand a complex concept. If you need to know which topic or my current level, ask me first."
                ),
                QuickActionOption(
                    title: String(localized: "Summarize a topic in depth", bundle: .module),
                    prompt: "Help me get a deep understanding of a topic. If you need to know which topic, please ask."
                ),
                QuickActionOption(
                    title: String(localized: "Compare two technologies or approaches", bundle: .module),
                    prompt: "I'd like to compare two technologies or approaches. If you need to know which ones, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Create a study plan", bundle: .module),
                    prompt: "Help me create a study plan. If you need to know the subject and my goals, please ask."
                ),
            ]
        ),
        QuickActionItem(
            id: "code",
            label: String(localized: "Code", bundle: .module),
            icon: "chevron.left.forwardslash.chevron.right",
            options: [
                QuickActionOption(
                    title: String(localized: "Debug an issue in my code", bundle: .module),
                    prompt: "I need help debugging an issue. If you need to see the code or error message, let me know."
                ),
                QuickActionOption(
                    title: String(localized: "Write a function or algorithm", bundle: .module),
                    prompt: "I need help writing a function or algorithm. If you need more details about the requirements, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Review and improve code", bundle: .module),
                    prompt: "I'd like you to review and improve some code. If you need me to share it, just ask."
                ),
                QuickActionOption(
                    title: String(localized: "Explain how something works", bundle: .module),
                    prompt: "Help me understand how a piece of code or technology works. If you need to know which one, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Set up a project or tool", bundle: .module),
                    prompt: "Help me set up a project or development tool. If you need to know the stack or requirements, please ask."
                ),
            ]
        ),
        QuickActionItem(
            id: "brainstorm",
            label: String(localized: "Brainstorm", bundle: .module),
            icon: "lightbulb",
            options: [
                QuickActionOption(
                    title: String(localized: "Generate creative ideas", bundle: .module),
                    prompt: "Help me brainstorm creative ideas. If you need to know the topic or constraints, ask me first."
                ),
                QuickActionOption(
                    title: String(localized: "Solve a problem from multiple angles", bundle: .module),
                    prompt: "I want to explore a problem from multiple perspectives. If you need to know what the problem is, please ask."
                ),
                QuickActionOption(
                    title: String(localized: "Plan a project or strategy", bundle: .module),
                    prompt: "Help me plan a project or strategy. If you need more context about the goals, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Come up with names or titles", bundle: .module),
                    prompt: "Help me come up with names or titles. If you need to know what it's for, please ask."
                ),
            ]
        ),
    ]

    /// Priority order: which connectors to show first (max 4 shown).
    static let connectorPriority: [String] = [
        "google.gmail",
        "google.calendar",
        "google.drive",
        "microsoft.outlook",
        "microsoft.calendar",
        "microsoft.onedrive",
        "dev.github",
        "dev.notion",
        "dev.linear",
        "wp.mcm",
    ]

    /// Connector-specific quick actions with relevant prompts.
    static let connectorActions: [String: QuickActionItem] = [
        "google.gmail": QuickActionItem(
            id: "google.gmail",
            label: String(localized: "From Gmail", bundle: .module),
            icon: "envelope",
            options: [
                QuickActionOption(
                    title: String(localized: "Which subscribed emails do I usually leave unread?", bundle: .module),
                    prompt: "Using @fetch gmail, tell me which subscribed emails I usually leave unread. Use any connector that is useful and start once you have enough information."
                ),
                QuickActionOption(
                    title: String(localized: "Review my emails and tell me if I'm missing something important", bundle: .module),
                    prompt: "Using @fetch gmail, review my recent emails and tell me if I'm missing something important. If you need more context, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Extract key points from my latest work emails", bundle: .module),
                    prompt: "Using @fetch gmail, extract the key points from my latest work emails. If you need to know which timeframe, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Summarize my unread emails", bundle: .module),
                    prompt: "Using @fetch gmail, summarize my unread emails. Group them by priority and tell me which ones need a response."
                ),
                QuickActionOption(
                    title: String(localized: "Draft replies to my pending emails", bundle: .module),
                    prompt: "Using @fetch gmail, check my emails that need a reply and draft responses. If you need more context about my tone or preferences, ask me."
                ),
            ]
        ),
        "google.calendar": QuickActionItem(
            id: "google.calendar",
            label: String(localized: "From Calendar", bundle: .module),
            icon: "calendar",
            options: [
                QuickActionOption(
                    title: String(localized: "What's on my schedule today?", bundle: .module),
                    prompt: "Using @fetch google.calendar, show me what's on my schedule today. Highlight anything urgent or that needs preparation."
                ),
                QuickActionOption(
                    title: String(localized: "Find free time this week for a meeting", bundle: .module),
                    prompt: "Using @fetch google.calendar, find available slots this week where I could schedule a meeting. If you need to know the duration, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Summarize my week ahead", bundle: .module),
                    prompt: "Using @fetch google.calendar, give me an overview of my upcoming week. Flag any conflicts or back-to-back meetings."
                ),
                QuickActionOption(
                    title: String(localized: "Help me prepare for my next meeting", bundle: .module),
                    prompt: "Using @fetch google.calendar, check my next meeting and help me prepare. If you need more context, ask me."
                ),
            ]
        ),
        "google.drive": QuickActionItem(
            id: "google.drive",
            label: String(localized: "From Drive", bundle: .module),
            icon: "externaldrive",
            options: [
                QuickActionOption(
                    title: String(localized: "Show my recently modified files", bundle: .module),
                    prompt: "Using @fetch google.drive, show me my recently modified files. Highlight anything shared with me that I haven't opened yet."
                ),
                QuickActionOption(
                    title: String(localized: "Find files related to a project", bundle: .module),
                    prompt: "Using @fetch google.drive, find files related to a specific project. If you need to know which project, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Summarize a document from my Drive", bundle: .module),
                    prompt: "Using @fetch google.drive, read and summarize a document. If you need to know which one, ask me."
                ),
            ]
        ),
        "microsoft.outlook": QuickActionItem(
            id: "microsoft.outlook",
            label: String(localized: "From Outlook", bundle: .module),
            icon: "envelope",
            options: [
                QuickActionOption(
                    title: String(localized: "Summarize my unread Outlook emails", bundle: .module),
                    prompt: "Using @fetch microsoft.outlook, summarize my unread emails. Group them by priority and tell me which ones need a response."
                ),
                QuickActionOption(
                    title: String(localized: "Review emails and flag what's important", bundle: .module),
                    prompt: "Using @fetch microsoft.outlook, review my recent emails and tell me if I'm missing something important."
                ),
                QuickActionOption(
                    title: String(localized: "Draft replies to pending Outlook emails", bundle: .module),
                    prompt: "Using @fetch microsoft.outlook, check emails that need a reply and help me draft responses. If you need more context, ask me."
                ),
            ]
        ),
        "microsoft.calendar": QuickActionItem(
            id: "microsoft.calendar",
            label: String(localized: "From Outlook Calendar", bundle: .module),
            icon: "calendar",
            options: [
                QuickActionOption(
                    title: String(localized: "What's on my Outlook schedule today?", bundle: .module),
                    prompt: "Using @fetch microsoft.calendar, show me what's on my schedule today. Highlight anything urgent."
                ),
                QuickActionOption(
                    title: String(localized: "Find free time for a meeting", bundle: .module),
                    prompt: "Using @fetch microsoft.calendar, find available slots this week for a meeting. If you need the duration, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Summarize my Outlook week ahead", bundle: .module),
                    prompt: "Using @fetch microsoft.calendar, give me an overview of my upcoming week. Flag any conflicts."
                ),
            ]
        ),
        "microsoft.onedrive": QuickActionItem(
            id: "microsoft.onedrive",
            label: String(localized: "From OneDrive", bundle: .module),
            icon: "externaldrive",
            options: [
                QuickActionOption(
                    title: String(localized: "Show my recently modified OneDrive files", bundle: .module),
                    prompt: "Using @fetch microsoft.onedrive, show me my recently modified files."
                ),
                QuickActionOption(
                    title: String(localized: "Find OneDrive files related to a project", bundle: .module),
                    prompt: "Using @fetch microsoft.onedrive, find files related to a project. If you need to know which one, ask me."
                ),
            ]
        ),
        "dev.github": QuickActionItem(
            id: "dev.github",
            label: String(localized: "From GitHub", bundle: .module),
            icon: "chevron.left.forwardslash.chevron.right",
            options: [
                QuickActionOption(
                    title: String(localized: "Show my open pull requests", bundle: .module),
                    prompt: "Using @fetch dev.github, show me my open pull requests. Highlight any that need review or have conflicts."
                ),
                QuickActionOption(
                    title: String(localized: "Review my assigned issues", bundle: .module),
                    prompt: "Using @fetch dev.github, list my assigned issues. If you need to know which repo, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Summarize recent activity in a repository", bundle: .module),
                    prompt: "Using @fetch dev.github, summarize recent commits and PRs in a repository. If you need to know which one, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Check CI status of my latest PRs", bundle: .module),
                    prompt: "Using @fetch dev.github, check the CI/CD status of my latest pull requests and tell me if anything failed."
                ),
            ]
        ),
        "dev.notion": QuickActionItem(
            id: "dev.notion",
            label: String(localized: "From Notion", bundle: .module),
            icon: "doc.text",
            options: [
                QuickActionOption(
                    title: String(localized: "Search my Notion pages", bundle: .module),
                    prompt: "Using @fetch dev.notion, search my Notion workspace. If you need to know what to search for, ask me."
                ),
                QuickActionOption(
                    title: String(localized: "Summarize a Notion page", bundle: .module),
                    prompt: "Using @fetch dev.notion, read and summarize a page from my workspace. If you need to know which one, ask me."
                ),
            ]
        ),
        "dev.linear": QuickActionItem(
            id: "dev.linear",
            label: String(localized: "From Linear", bundle: .module),
            icon: "list.bullet.rectangle",
            options: [
                QuickActionOption(
                    title: String(localized: "Show my assigned Linear issues", bundle: .module),
                    prompt: "Using @fetch dev.linear, show me my assigned issues. Group them by priority."
                ),
                QuickActionOption(
                    title: String(localized: "Summarize current sprint progress", bundle: .module),
                    prompt: "Using @fetch dev.linear, summarize the progress of the current sprint. Highlight blockers."
                ),
            ]
        ),
        "wp.mcm": QuickActionItem(
            id: "wp.mcm",
            label: String(localized: "From WordPress", bundle: .module),
            icon: "globe",
            options: [
                QuickActionOption(
                    title: String(localized: "Check my site's recent posts", bundle: .module),
                    prompt: "Using @fetch wp.mcm, show me the latest posts on my WordPress site."
                ),
                QuickActionOption(
                    title: String(localized: "Review pending comments", bundle: .module),
                    prompt: "Using @fetch wp.mcm, show me pending comments that need moderation."
                ),
                QuickActionOption(
                    title: String(localized: "Check site health and errors", bundle: .module),
                    prompt: "Using @fetch wp.mcm, check my WordPress site health and report any errors or warnings."
                ),
            ]
        ),
    ]
}

private struct QuickActionOption: Identifiable {
    let id = UUID()
    let title: String
    let prompt: String
}

// MARK: - Quick Action Chip

private struct QuickActionChip: View {
    let icon: String
    let label: String
    var isExpanded: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isExpanded ? Color.accentColor.opacity(0.2) : Color.clear)
            .background(.quaternary.opacity(0.4))
            .clipShape(Capsule())
            .liquidGlassCapsule(interactive: false)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isExpanded ? .primary : .secondary)
    }
}

// MARK: - Quick Action Panel (expandable sub-options)

private struct QuickActionPanel: View {
    let action: QuickActionItem
    let onSelect: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: action.icon)
                    .font(.caption)
                Text(action.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Options list
            ForEach(Array(action.options.enumerated()), id: \.element.id) { index, option in
                Button {
                    onSelect(option.prompt)
                } label: {
                    HStack {
                        Text(option.title)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                if index < action.options.count - 1 {
                    Divider()
                        .padding(.horizontal, 14)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: NSColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0)))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(nsColor: NSColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1.0)), lineWidth: 1)
                }
        }
        .frame(maxWidth: 500)
    }
}
