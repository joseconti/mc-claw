import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Multi-line Text Input (NSTextView wrapper)

/// NSTextView wrapper that supports Shift+Enter for newlines and Enter to send.
/// Height adapts to content: single line when empty, grows as text is added.
struct MultiLineTextInput: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont
    var minHeight: CGFloat = 22
    var maxHeight: CGFloat = 150
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> AutoSizingScrollView {
        let scrollView = AutoSizingScrollView()
        scrollView.minContentHeight = minHeight
        scrollView.maxContentHeight = maxHeight
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = SubmitTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.placeholderString = placeholder

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: AutoSizingScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitTextView else { return }
        if textView.string != text {
            textView.string = text
            scrollView.invalidateIntrinsicContentSize()
        }
        textView.placeholderString = placeholder
        textView.onSubmit = onSubmit
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultiLineTextInput
        weak var textView: NSTextView?

        init(_ parent: MultiLineTextInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            // Trigger SwiftUI layout update for height change
            if let scrollView = textView.enclosingScrollView as? AutoSizingScrollView {
                scrollView.invalidateIntrinsicContentSize()
            }
        }
    }
}

/// ScrollView that reports intrinsic height based on its text content.
class AutoSizingScrollView: NSScrollView {
    var minContentHeight: CGFloat = 22
    var maxContentHeight: CGFloat = 150

    override var intrinsicContentSize: NSSize {
        guard let textView = documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minContentHeight)
        }
        layoutManager.ensureLayout(for: container)
        let textHeight = layoutManager.usedRect(for: container).height
        let insets = textView.textContainerInset
        let totalHeight = textHeight + insets.height * 2
        let clamped = min(max(totalHeight, minContentHeight), maxContentHeight)
        return NSSize(width: NSView.noIntrinsicMetric, height: clamped)
    }
}

/// Custom NSTextView that sends on Enter and inserts newline on Shift+Enter.
private class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var placeholderString: String? {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        // Enter/Return without Shift → send
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        // Shift+Enter → insert newline (default behavior)
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw placeholder when empty
        if string.isEmpty, let placeholder = placeholderString {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? NSFont.systemFont(ofSize: 15)
            ]
            let inset = textContainerInset
            let rect = NSRect(
                x: inset.width + 5,
                y: inset.height,
                width: bounds.width - inset.width * 2 - 5,
                height: bounds.height - inset.height * 2
            )
            NSString(string: placeholder).draw(in: rect, withAttributes: attrs)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        // Notify scroll view to resize
        if let scrollView = enclosingScrollView as? AutoSizingScrollView {
            scrollView.invalidateIntrinsicContentSize()
        }
    }
}

/// Centered input bar styled like Claude Desktop.
/// - `compact: false` (default) — Welcome screen mode: taller, more padding.
/// - `compact: true` — Conversation mode: slim single-line, at the bottom.
struct ChatInputBar: View {
    let onSend: (String, [Attachment]) -> Void
    let onAbort: () -> Void
    let isWorking: Bool
    var compact: Bool = false
    var onImageGenerate: ((String) -> Void)?

    @Environment(AppState.self) private var appState
    @State private var text: String = ""
    @State private var attachments: [Attachment] = []
    @State private var voiceMode = VoiceModeService.shared
    @State private var imageMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Attachments preview
            if !attachments.isEmpty {
                attachmentsRow
            }

            // Main input area
            VStack(spacing: 0) {
                // Text field
                MultiLineTextInput(
                    text: $text,
                    placeholder: voiceMode.isActive
                        ? String(localized: "Voice Mode active...", bundle: .module)
                        : imageMode
                            ? String(localized: "Describe the image you want to create...", bundle: .module)
                            : String(localized: "Type / for commands", bundle: .module),
                    font: .systemFont(ofSize: compact ? 14 : 16),
                    minHeight: compact ? 36 : 80,
                    maxHeight: compact ? 120 : 200,
                    onSubmit: {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            sendMessage()
                        }
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, compact ? 10 : 16)
                .padding(.horizontal, 14)
                .padding(.bottom, compact ? 6 : 12)

                // Bottom row: attach + voice on left, send on right
                HStack(spacing: 8) {
                    // Attach
                    attachButton

                    // Voice toggle
                    voiceButton

                    // Image generation toggle
                    imageGenButton

                    Spacer()

                    // Send / Abort button
                    sendButton
                }
                .padding(.horizontal, 12)
                .padding(.bottom, compact ? 6 : 10)
            }
            .background {
                RoundedRectangle(cornerRadius: compact ? 16 : 20)
                    .fill(Theme.cardBackground)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 16 : 20)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    }
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 20)
            .padding(.vertical, compact ? 6 : 10)
        }
        .animation(.easeInOut(duration: 0.2), value: voiceMode.isActive)
        .onChange(of: appState.prefillText) { _, newValue in
            if let newValue, !newValue.isEmpty {
                text = newValue
                appState.prefillText = nil
            }
        }
        .onChange(of: voiceMode.currentTranscript) { _, transcript in
            if voiceMode.isActive {
                text = transcript
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text(attachment.filename)
                            .lineLimit(1)
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Capsule())
                    .liquidGlassCapsule(interactive: false)
                }
            }
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var attachButton: some View {
        Button(action: openFilePicker) {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.quaternary.opacity(0.5))
                .clipShape(Circle())
                .liquidGlassCircle()
        }
        .buttonStyle(.plain)
        .help(String(localized: "Attach files", bundle: .module))
    }

    @ViewBuilder
    private var voiceButton: some View {
        Button {
            voiceMode.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: voiceModeIcon)
                    .font(.subheadline)
                    .foregroundStyle(voiceMode.isActive ? .white : .secondary)
                    .symbolEffect(.pulse, isActive: voiceMode.state == .listening)
                Text(String(localized: "Voice", bundle: .module))
                    .font(.callout.weight(voiceMode.isActive ? .semibold : .regular))
                    .foregroundStyle(voiceMode.isActive ? .white : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if voiceMode.isActive {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.35))
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                } else {
                    Capsule().fill(.quaternary.opacity(0.5))
                }
            }
            .clipShape(Capsule())
            .liquidGlassCapsule(interactive: false)
        }
        .buttonStyle(.plain)
        .help("Voice Mode (Cmd+Shift+V)")
        .keyboardShortcut("v", modifiers: [.command, .shift])
    }

    @ViewBuilder
    private var imageGenButton: some View {
        if hasImageCapableCLI {
            Button {
                imageMode.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: imageMode ? "photo.fill" : "photo")
                        .font(.subheadline)
                        .foregroundStyle(imageMode ? .white : .secondary)
                    Text(String(localized: "Image", bundle: .module))
                        .font(.callout)
                        .foregroundStyle(imageMode ? .white : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if imageMode {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.35))
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                    } else {
                        Capsule().fill(.quaternary.opacity(0.5))
                    }
                }
                .clipShape(Capsule())
                .liquidGlassCapsule(interactive: false)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Generate Image", bundle: .module))
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if isWorking {
            Button(action: onAbort) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Color.accentColor : Color.gray.opacity(0.2))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var voiceModeIcon: String {
        switch voiceMode.state {
        case .off: "mic"
        case .listening: "mic.fill"
        case .speaking: "speaker.wave.2.fill"
        case .processing: "ellipsis"
        }
    }

    private var voiceModeColor: Color {
        switch voiceMode.state {
        case .off: .secondary
        case .listening: .green
        case .speaking: .blue
        case .processing: .orange
        }
    }

    private var hasImageCapableCLI: Bool {
        appState.availableCLIs.contains {
            $0.isInstalled && $0.isAuthenticated && $0.capabilities.supportsImageGeneration
        }
    }

    private func sendMessage() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if imageMode, let onImage = onImageGenerate {
            onImage(trimmed)
            text = ""
            imageMode = false
        } else {
            onSend(trimmed, attachments)
            text = ""
            attachments = []
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        panel.message = "Select files to attach"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let fileSize = attrs[.size] as? Int64 else { continue }

            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

            let attachment = Attachment(
                filename: url.lastPathComponent,
                mimeType: mimeType,
                filePath: url.path,
                fileSize: fileSize
            )
            attachments.append(attachment)
        }
    }
}
