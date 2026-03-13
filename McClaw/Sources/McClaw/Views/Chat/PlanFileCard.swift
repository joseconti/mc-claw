import SwiftUI

/// Compact clickable card shown in a message bubble when a plan file is detected.
/// Clicking opens the PlanDetailPanel in the right side of ChatWindow.
struct PlanFileCard: View {
    let filePath: String
    @Environment(AppState.self) private var appState

    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                if appState.openPlanFilePath == filePath {
                    appState.openPlanFilePath = nil
                } else {
                    appState.openPlanFilePath = filePath
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background(.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName.replacingOccurrences(of: ".md", with: ""))
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(String(localized: "Plan File · MD", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: appState.openPlanFilePath == filePath ? "chevron.right.circle.fill" : "chevron.right.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.orange.opacity(appState.openPlanFilePath == filePath ? 0.5 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Right-side panel that displays the full content of a plan file in markdown.
struct PlanDetailPanel: View {
    let filePath: String
    @Environment(AppState.self) private var appState
    @State private var content: String = ""
    @State private var isLoading: Bool = true

    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.orange)
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()

                // Open in Finder
                Button {
                    NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Reveal in Finder", bundle: .module))

                // Copy content
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Copy Plan Content", bundle: .module))

                // Close
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        appState.openPlanFilePath = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if content.isEmpty {
                Spacer()
                Text(String(localized: "Plan file is empty", bundle: .module))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    MarkdownContentView(content: content)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 320, idealWidth: 400, maxWidth: 500)
        .background(.ultraThinMaterial)
        .task(id: filePath) {
            isLoading = true
            content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            isLoading = false
        }
    }
}
