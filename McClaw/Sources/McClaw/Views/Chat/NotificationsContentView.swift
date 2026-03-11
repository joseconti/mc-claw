import SwiftUI

/// Main content view for the Notifications sidebar section.
/// Shows schedule execution results with native macOS notification integration.
struct NotificationsContentView: View {
    @State private var store = ScheduleNotificationStore.shared
    @State private var selectedId: String?
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            nativeBanner
            content
        }
        .alert("Clear all notifications?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text("This will remove all notification history. This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.title3.weight(.semibold))
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if store.unreadCount > 0 {
                    Button("Mark All Read") {
                        store.markAllAsRead()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if !store.entries.isEmpty {
                    Button {
                        confirmClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Clear all")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        if store.entries.isEmpty { return "No notifications" }
        let unread = store.unreadCount
        if unread > 0 {
            return "\(unread) unread of \(store.entries.count)"
        }
        return "\(store.entries.count) notifications"
    }

    // MARK: - Native Notifications Banner

    @ViewBuilder
    private var nativeBanner: some View {
        if !store.nativeNotificationsEnabled {
            HStack(spacing: 8) {
                Image(systemName: "bell.slash")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS notifications are disabled")
                        .font(.callout.weight(.medium))
                    Text("Enable them to receive schedule results as system notifications.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Enable") {
                    store.requestNativePermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                notificationList
                    .frame(width: 300)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No notifications yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("When your scheduled actions run, their results will appear here.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if !store.nativeNotificationsEnabled {
                Button("Enable macOS Notifications") {
                    store.requestNativePermission()
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Notification List

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.entries) { entry in
                    notificationRow(entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedId = entry.id
                            if !entry.isRead {
                                store.markAsRead(entry.id)
                            }
                        }
                        .contextMenu {
                            if !entry.isRead {
                                Button("Mark as Read") {
                                    store.markAsRead(entry.id)
                                }
                            }
                            Button("Delete", role: .destructive) {
                                store.delete(entry.id)
                                if selectedId == entry.id {
                                    selectedId = nil
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .background(.background)
    }

    private func notificationRow(_ entry: ScheduleNotification) -> some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon(entry.status)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if !entry.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(entry.scheduleName)
                        .font(.subheadline.weight(entry.isRead ? .regular : .medium))
                        .lineLimit(1)
                }
                Text(entry.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(relativeTime(entry.timestamp))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selectedId == entry.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
    }

    private func statusIcon(_ status: ScheduleNotification.Status) -> some View {
        let (icon, color): (String, Color) = switch status {
        case .success: ("checkmark.circle.fill", .green)
        case .error: ("xmark.circle.fill", .red)
        case .timeout: ("clock.badge.exclamationmark", .orange)
        }
        return Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 24)
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(alignment: .center) {
                        statusIcon(entry.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.scheduleName)
                                .font(.title3.weight(.semibold))
                            HStack(spacing: 6) {
                                statusPill(entry.status)
                                if let provider = entry.provider, !provider.isEmpty {
                                    Text(provider)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.delete(entry.id)
                            selectedId = nil
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    // Timestamp
                    LabeledContent("Time") {
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.callout)
                    }

                    Divider()

                    // Result content
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Result")
                            .font(.headline)
                        Text(entry.summary)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Text("Select a notification to view details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedEntry: ScheduleNotification? {
        guard let id = selectedId else { return nil }
        return store.entries.first { $0.id == id }
    }

    private func statusPill(_ status: ScheduleNotification.Status) -> some View {
        let (text, color): (String, Color) = switch status {
        case .success: ("Success", .green)
        case .error: ("Error", .red)
        case .timeout: ("Timeout", .orange)
        }
        return Text(text)
            .font(.subheadline)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .liquidGlassCapsule(interactive: false)
    }

    private func relativeTime(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "Just now" }
        let minutes = Int(delta / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
