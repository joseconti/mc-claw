import SwiftUI

/// Main content view for the Trash section with bulk actions (select, restore, delete).
struct TrashContentView: View {
    @State private var sessionStore = SessionStore.shared
    @State private var selectedIds: Set<String> = []
    @State private var showEmptyConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trash")
                        .font(.title.weight(.bold))
                    Text("\(sessionStore.trashedSessions.count) conversation\(sessionStore.trashedSessions.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !sessionStore.trashedSessions.isEmpty {
                    Button(role: .destructive) {
                        showEmptyConfirmation = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            // Bulk action bar
            if !sessionStore.trashedSessions.isEmpty {
                bulkActionBar

                Divider()
                    .padding(.horizontal, 24)
            }

            // Content
            ScrollView {
                if sessionStore.trashedSessions.isEmpty {
                    emptyTrashView
                } else {
                    VStack(spacing: 0) {
                        ForEach(sessionStore.trashedSessions) { session in
                            trashRow(session: session)

                            if session.id != sessionStore.trashedSessions.last?.id {
                                Divider()
                                    .padding(.horizontal, 32)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
        }
        .confirmationDialog(
            "Empty Trash",
            isPresented: $showEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Permanently", role: .destructive) {
                sessionStore.emptyTrash()
                selectedIds.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(sessionStore.trashedSessions.count) conversation\(sessionStore.trashedSessions.count == 1 ? "" : "s"). This action cannot be undone.")
        }
    }

    // MARK: - Bulk Action Bar

    @ViewBuilder
    private var bulkActionBar: some View {
        HStack(spacing: 12) {
            // Select All / Deselect All
            Button {
                if selectedIds.count == sessionStore.trashedSessions.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(sessionStore.trashedSessions.map(\.id))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(allSelected ? Color.accentColor : .secondary)
                    Text(allSelected ? "Deselect All" : "Select All")
                        .font(.callout)
                }
            }
            .buttonStyle(.plain)

            if !selectedIds.isEmpty {
                Text("\(selectedIds.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                // Restore selected
                Button {
                    restoreSelected()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)

                // Delete selected permanently
                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("Delete Permanently", systemImage: "trash.slash")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var allSelected: Bool {
        !sessionStore.trashedSessions.isEmpty &&
        selectedIds.count == sessionStore.trashedSessions.count
    }

    // MARK: - Trash Row

    @ViewBuilder
    private func trashRow(session: SessionInfo) -> some View {
        HStack(spacing: 12) {
            // Checkbox
            Button {
                toggleSelection(session.id)
            } label: {
                Image(systemName: selectedIds.contains(session.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIds.contains(session.id) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)

            Image(systemName: "bubble.left")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let provider = session.cliProvider {
                        Text(provider.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }

                    Text("\(session.messageCount) message\(session.messageCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(session.lastMessageAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Per-row quick actions
            HStack(spacing: 4) {
                Button {
                    sessionStore.restoreFromTrash(sessionId: session.id)
                    selectedIds.remove(session.id)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Restore")

                Button {
                    sessionStore.deletePermanently(sessionId: session.id)
                    selectedIds.remove(session.id)
                } label: {
                    Image(systemName: "trash.slash")
                        .font(.callout)
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete Permanently")
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(selectedIds.contains(session.id) ? Color.accentColor.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(session.id)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyTrashView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Trash is empty")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Deleted conversations will appear here so you can restore them if needed.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Actions

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func restoreSelected() {
        for id in selectedIds {
            sessionStore.restoreFromTrash(sessionId: id)
        }
        selectedIds.removeAll()
    }

    private func deleteSelected() {
        for id in selectedIds {
            sessionStore.deletePermanently(sessionId: id)
        }
        selectedIds.removeAll()
    }
}
