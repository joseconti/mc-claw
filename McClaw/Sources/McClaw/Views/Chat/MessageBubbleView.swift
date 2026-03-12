import SwiftUI
import AppKit
import McClawKit

/// Renders a single chat message styled like Claude Desktop.
/// User messages: right-aligned with dark bubble.
/// Assistant messages: left-aligned, no bubble, with avatar.
struct MessageBubbleView: View {
    let message: ChatMessage
    var userAvatarImage: NSImage?
    var fontSize: CGFloat = 16
    var fontFamily: ChatFontFamily = .default
    var isLastMessage: Bool = false

    var body: some View {
        if message.role == .system {
            systemMessage
        } else if message.role == .user {
            userMessage
        } else {
            assistantMessage
        }
    }

    // MARK: - User Message (right-aligned, bubble)

    @State private var isHoveringUserMessage = false

    @ViewBuilder
    private var userMessage: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 6) {
                // Role label
                HStack(spacing: 8) {
                    Text("You")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    userAvatar
                }

                // Message bubble
                VStack(alignment: .leading, spacing: 8) {
                    markdownContent
                        .textSelection(.enabled)

                    // Attachments
                    if !message.attachments.isEmpty {
                        attachmentsRow
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.userBubble)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                // Copy action bar for user messages
                if !message.content.isEmpty {
                    HStack {
                        Spacer()
                        MessageActionBar(content: message.content)
                            .opacity(isHoveringUserMessage ? 1 : 0)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringUserMessage = hovering
            }
        }
    }

    // MARK: - Assistant Message (left-aligned, no bubble)

    @State private var isHoveringMessage = false

    @ViewBuilder
    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            // McClaw avatar
            assistantAvatar

            VStack(alignment: .leading, spacing: 8) {
                // Role label
                Text("McClaw")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                // Message text
                markdownContent
                    .textSelection(.enabled)

                // Tool calls
                ForEach(message.toolCalls) { toolCall in
                    ToolCallCard(toolCall: toolCall)
                }

                // Shimmer placeholder while generating image
                if message.isGeneratingImage && message.isStreaming {
                    ShimmerImagePlaceholder()
                }

                // Generated images
                if !message.generatedImages.isEmpty {
                    GeneratedImagesGallery(images: message.generatedImages)
                }

                // Install progress
                if let planId = message.installPlanId {
                    InstallProgressView(planId: planId)
                }

                // Interactive prompts
                if !message.interactivePrompts.isEmpty {
                    let service = InteractivePromptService.shared
                    ForEach(Array(message.interactivePrompts.enumerated()), id: \.element.id) { index, prompt in
                        InteractivePromptCard(
                            prompt: prompt,
                            isActive: service.phase == .presenting
                                && service.currentIndex == index
                                && service.currentPrompts.contains(where: { $0.id == prompt.id }),
                            currentIndex: index,
                            totalCount: message.interactivePrompts.count,
                            existingResponse: message.promptResponses.first(where: { $0.promptId == prompt.id })
                        )
                    }
                }

                // Streaming indicator (only text streaming, not image generation)
                if message.isStreaming && !message.isGeneratingImage {
                    ThinkingWordsView()
                }

                // Copy action bar — visible on hover or always on last message
                if !message.content.isEmpty && !message.isStreaming {
                    MessageActionBar(
                        content: message.content,
                        alwaysVisible: isLastMessage
                    )
                    .opacity(isHoveringMessage || isLastMessage ? 1 : 0)
                }
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringMessage = hovering
            }
        }
    }

    // MARK: - System Message (centered, subtle)

    @ViewBuilder
    private var systemMessage: some View {
        HStack {
            Spacer()
            markdownContent
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    // MARK: - Avatars

    @ViewBuilder
    private var userAvatar: some View {
        Group {
            if let avatar = userAvatarImage {
                Image(nsImage: avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(Color.accentColor.gradient)
                    .overlay {
                        Text(userInitials)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var assistantAvatar: some View {
        Group {
            if let url = Bundle.module.url(forResource: "mcclaw-logo", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Circle()
                    .fill(.orange.gradient)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    // MARK: - Content

    @ViewBuilder
    private var markdownContent: some View {
        MarkdownContentView(content: message.content, fontSize: fontSize, fontFamily: fontFamily)
    }

    @ViewBuilder
    private var attachmentsRow: some View {
        HStack(spacing: 6) {
            ForEach(message.attachments) { attachment in
                Label(attachment.filename, systemImage: "paperclip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Capsule())
                    .liquidGlassCapsule(interactive: false)
            }
        }
    }

    private var userInitials: String {
        let name = NSFullUserName()
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "U" : initials
    }
}

/// Card showing a tool call and its result.
struct ToolCallCard: View {
    let toolCall: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: toolIconName)
                    .font(.subheadline)
                Text(toolCall.name)
                    .font(.callout.weight(.medium))
                Spacer()
                statusIcon
            }

            if let result = toolCall.result {
                Text(result)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var toolIconName: String {
        let name = toolCall.name
        if name.contains("file") { return "doc" }
        if name.contains("web") { return "globe" }
        if name.contains("exec") || name.contains("run") { return "terminal" }
        if name.contains("search") { return "magnifyingglass" }
        return "wrench"
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toolCall.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .scaleEffect(0.5)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

/// Claude-style action bar with copy button. Shows on hover with dark background on icon hover.
struct MessageActionBar: View {
    let content: String
    var alwaysVisible: Bool = false

    @State private var copied = false

    var body: some View {
        HStack(spacing: 2) {
            ActionBarButton(
                icon: copied ? "checkmark" : "doc.on.doc",
                tooltip: copied ? "Copied" : "Copy"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            }
        }
        .padding(.top, 4)
    }
}

/// Gallery showing generated images with download/save actions.
struct GeneratedImagesGallery: View {
    let images: [GeneratedImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(images) { image in
                GeneratedImageCard(image: image)
            }
        }
    }
}

/// Card displaying a single generated image with modern styling and save-to-disk action.
private struct GeneratedImageCard: View {
    let image: GeneratedImage
    @State private var nsImage: NSImage?
    @State private var isHovered = false
    @State private var saved = false
    @Environment(\.showImageOverlay) private var showImageOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let nsImage {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 480, maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        .scaleEffect(isHovered ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)

                    // Save button overlay — glass pill
                    if isHovered {
                        Button {
                            saveImage()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: saved ? "checkmark.circle.fill" : "arrow.down.to.line")
                                    .font(.system(size: 13, weight: .medium))
                                Text(String(localized: "save_image", bundle: .module))
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(saved ? .green : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture {
                    showImageOverlay?(image)
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            } else {
                // Loading/error placeholder
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary.opacity(0.3))
                    .frame(width: 200, height: 150)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
            }

            // Caption
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text(String(localized: "Generated by", bundle: .module) + " " + image.providerUsed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        let path = image.filePath
        DispatchQueue.global(qos: .userInitiated).async {
            if let img = NSImage(contentsOfFile: path) {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.3)) {
                        nsImage = img
                    }
                }
            }
        }
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = URL(fileURLWithPath: image.filePath).lastPathComponent
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: image.filePath),
                to: url
            )
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saved = false
            }
        } catch {
            // Silently fail — user can retry
        }
    }
}

/// Individual action bar button — icon with dark fill on hover, like Claude.
private struct ActionBarButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? .white : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color(.darkGray) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}
