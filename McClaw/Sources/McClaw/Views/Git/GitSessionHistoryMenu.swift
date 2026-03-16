import SwiftUI

/// Menu button showing conversation history for the current Git repository.
/// Allows switching between past sessions, starting new conversations, and deleting old ones.
struct GitSessionHistoryMenu: View {
    let sessions: [SessionInfo]
    let currentSessionId: String?
    let onSelect: (SessionInfo) -> Void
    let onNewSession: () -> Void
    let onDelete: (SessionInfo) -> Void

    var body: some View {
        Menu {
            Button {
                onNewSession()
            } label: {
                Label(String(localized: "git_session_new", bundle: .appModule), systemImage: "plus")
            }

            if !sessions.isEmpty {
                Divider()

                ForEach(sessions) { session in
                    Menu {
                        Button {
                            onSelect(session)
                        } label: {
                            Label(String(localized: "git_session_open", bundle: .appModule), systemImage: "arrow.right.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            onDelete(session)
                        } label: {
                            Label(String(localized: "git_session_delete", bundle: .appModule), systemImage: "trash")
                        }
                    } label: {
                        HStack {
                            if session.id == currentSessionId {
                                Image(systemName: "checkmark")
                            }
                            Text(session.title)
                                .lineLimit(1)
                            Text("(\(session.messageCount))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.callout)
                if !sessions.isEmpty {
                    Text("\(sessions.count)")
                        .font(.caption2.weight(.medium))
                }
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "git_session_history", bundle: .appModule))
    }
}
