import SwiftUI

/// Which section the sidebar is currently showing.
enum SidebarSection: Hashable {
    case chats
    case projects
    case projectDetail(String) // projectId
    case schedules
    case notifications
    case trash
}

/// Sidebar for the chat window, showing conversations and navigation.
struct ChatSidebar: View {
    @Binding var currentSection: SidebarSection
    let onNewChat: () -> Void
    let onSelectSession: (SessionInfo) -> Void
    let onDeleteSession: (String) -> Void

    @Environment(AppState.self) private var appState
    @State private var sessionStore = SessionStore.shared
    @State private var projectStore = ProjectStore.shared
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // New conversation button
            Button {
                currentSection = .chats
                onNewChat()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                    Text("New Conversation")
                        .font(.body)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.horizontal, 6)

            // Search (only when showing chats)
            if currentSection == .chats {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()
                .padding(.horizontal, 12)

            // Navigation items
            VStack(alignment: .leading, spacing: 2) {
                SidebarNavItem(
                    icon: "bubble.left.and.bubble.right",
                    label: "Chats",
                    isActive: currentSection == .chats
                ) {
                    currentSection = .chats
                }
                SidebarNavItem(
                    icon: "folder",
                    label: "Projects",
                    isActive: currentSection == .projects || isInProjectDetail
                ) {
                    currentSection = .projects
                }
                SidebarNavItem(
                    icon: "calendar.badge.clock",
                    label: "Schedules",
                    isActive: currentSection == .schedules,
                    badge: CronJobsStore.shared.jobs.filter(\.enabled).count
                ) {
                    currentSection = .schedules
                }
                SidebarNavItem(
                    icon: "bell.badge",
                    label: "Notifications",
                    isActive: currentSection == .notifications,
                    badge: ScheduleNotificationStore.shared.unreadCount
                ) {
                    currentSection = .notifications
                }
                SidebarNavItem(
                    icon: "trash",
                    label: "Trash",
                    isActive: currentSection == .trash,
                    badge: sessionStore.trashedSessions.count
                ) {
                    currentSection = .trash
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 12)

            // Chat list (only in chats section)
            if currentSection == .chats {
                chatsListView
            }

            Spacer()

            // Bottom: User + Settings
            Divider()
            sidebarFooter
        }
        .background(.background)
        .onAppear {
            sessionStore.refreshIndex()
            projectStore.refreshIndex()
        }
    }

    private var isInProjectDetail: Bool {
        if case .projectDetail = currentSection { return true }
        return false
    }

    // MARK: - Chats List

    @ViewBuilder
    private var chatsListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                ForEach(filteredUnassignedSessions) { session in
                    SidebarSessionRow(
                        session: session,
                        isSelected: session.id == appState.currentSessionId
                    ) {
                        onSelectSession(session)
                    }
                    .contextMenu {
                        sessionContextMenu(session: session)
                    }
                }

                if filteredUnassignedSessions.isEmpty {
                    Text("No conversations yet")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
            }
        }
    }

    private var filteredUnassignedSessions: [SessionInfo] {
        let base = sessionStore.unassignedSessions
        if searchText.isEmpty {
            return Array(base.prefix(20))
        }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Session Context Menu

    @ViewBuilder
    private func sessionContextMenu(session: SessionInfo) -> some View {
        // Move to project submenu
        if !projectStore.projects.isEmpty {
            Menu("Move to Project") {
                ForEach(projectStore.projects) { project in
                    Button(project.name) {
                        projectStore.addSession(session.id, toProject: project.id)
                        sessionStore.refreshIndex()
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            deleteSession(session)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private func deleteSession(_ session: SessionInfo) {
        let sessionId = session.id
        // Remove from project if assigned
        if let projectId = session.projectId {
            projectStore.removeSession(sessionId, fromProject: projectId)
        }
        // Move to trash
        sessionStore.delete(sessionId: sessionId)
        // Notify ChatWindow to handle active session switch
        onDeleteSession(sessionId)
    }

    // MARK: - Footer

    @ViewBuilder
    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            // User avatar
            Group {
                if let avatar = appState.userAvatarImage {
                    Image(nsImage: avatar)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(Color.accentColor.gradient)
                        .overlay {
                            Text(userInitials)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(userName)
                    .font(.callout.weight(.medium))
                Text("v\(UpdaterService.shared.currentVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var userName: String {
        let name = NSFullUserName()
        return name.isEmpty ? "McClaw" : name
    }

    private var userInitials: String {
        let name = NSFullUserName()
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "MC" : initials
    }
}

// MARK: - Sidebar Components

private struct SidebarNavItem: View {
    let icon: String
    let label: String
    let isActive: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.callout)
                    .frame(width: 20)
                Text(label)
                    .font(.callout)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarSessionRow: View {
    let session: SessionInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(session.title)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}
