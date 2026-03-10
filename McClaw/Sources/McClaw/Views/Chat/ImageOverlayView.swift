import SwiftUI
import AppKit

/// Full-window image overlay with download capability.
/// Shown when user clicks on a generated image in chat or Multimedia gallery.
struct ImageOverlayView: View {
    let image: GeneratedImage
    let onDismiss: () -> Void

    @State private var nsImage: NSImage?
    @State private var saved = false

    var body: some View {
        ZStack {
            // Dimmed background — click to dismiss
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                // Top bar: info + close button
                HStack {
                    // Provider badge
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Text(image.providerUsed)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()

                    // Close button
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Large image
                if let nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(40)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }

                Spacer()

                // Bottom bar: prompt + save button
                HStack(spacing: 16) {
                    // Prompt text
                    Text(image.prompt)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Spacer()

                    // Save button
                    Button {
                        saveImage()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: saved ? "checkmark.circle.fill" : "arrow.down.to.line")
                                .font(.body)
                            Text(String(localized: "save_image", bundle: .module))
                                .font(.callout.weight(.medium))
                        }
                        .foregroundStyle(saved ? .green : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .onAppear { loadImage() }
    }

    private func loadImage() {
        let path = image.filePath
        DispatchQueue.global(qos: .userInitiated).async {
            if let img = NSImage(contentsOfFile: path) {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
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
