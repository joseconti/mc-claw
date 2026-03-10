import SwiftUI
import AppKit

/// Gallery view showing all generated images across sessions with a detail inspector.
struct MultimediaContentView: View {
    let onNavigateToChat: (String) -> Void
    let onShowOverlay: (GeneratedImage) -> Void

    @State private var imageIndexStore = ImageIndexStore.shared
    @State private var selectedImage: IndexedImage?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            if imageIndexStore.allImages.isEmpty {
                emptyState
            } else {
                HSplitView {
                    // Left: large image when selected, grid otherwise
                    if let selected = selectedImage {
                        selectedImageView(for: selected)
                    } else {
                        galleryGrid
                    }

                    // Right: metadata + actions panel
                    if let selected = selectedImage {
                        detailPanel(for: selected)
                            .frame(width: 300)
                    }
                }
            }
        }
        .onAppear {
            imageIndexStore.refreshIndex()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            Text(String(localized: "multimedia", bundle: .module))
                .font(.title2.weight(.bold))

            if !imageIndexStore.allImages.isEmpty {
                Text("\(imageIndexStore.allImages.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                imageIndexStore.refreshIndex()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "refresh", bundle: .module))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text(String(localized: "no_images_yet", bundle: .module))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(String(localized: "images_will_appear_here", bundle: .module))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gallery Grid

    @ViewBuilder
    private var galleryGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)],
                spacing: 12
            ) {
                ForEach(imageIndexStore.allImages) { indexed in
                    MultimediaGridItem(
                        image: indexed,
                        isSelected: selectedImage?.imageId == indexed.imageId
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedImage = indexed
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 300)
    }

    // MARK: - Selected Image View

    @ViewBuilder
    private func selectedImageView(for image: IndexedImage) -> some View {
        ZStack(alignment: .topLeading) {
            AsyncImageFromDisk(filePath: image.filePath, expandToFill: true)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedImage = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(String(localized: "Gallery", bundle: .module))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private func detailPanel(for image: IndexedImage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    metadataRow(
                        label: String(localized: "session_label", bundle: .module),
                        value: image.sessionTitle
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "prompt_label", bundle: .module))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(image.prompt)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    metadataRow(
                        label: String(localized: "provider_label", bundle: .module),
                        value: image.providerUsed
                    )

                    metadataRow(
                        label: String(localized: "created_label", bundle: .module),
                        value: image.timestamp.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                Divider()

                // Actions
                VStack(spacing: 8) {
                    Button {
                        saveImage(filePath: image.filePath)
                    } label: {
                        Label(String(localized: "save_to_disk", bundle: .module), systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        let generatedImage = GeneratedImage(
                            id: image.imageId,
                            filePath: image.filePath,
                            prompt: image.prompt,
                            providerUsed: image.providerUsed,
                            timestamp: image.timestamp
                        )
                        onShowOverlay(generatedImage)
                    } label: {
                        Label(String(localized: "open_full_screen", bundle: .module), systemImage: "arrow.up.left.and.arrow.down.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        onNavigateToChat(image.sessionId)
                    } label: {
                        Label(String(localized: "open_in_chat", bundle: .module), systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(16)
        }
        .background(Theme.sidebarBackground)
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func saveImage(filePath: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = URL(fileURLWithPath: filePath).lastPathComponent
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        try? FileManager.default.copyItem(
            at: URL(fileURLWithPath: filePath),
            to: url
        )
    }
}

// MARK: - Grid Item

/// A single thumbnail card in the Multimedia gallery grid.
private struct MultimediaGridItem: View {
    let image: IndexedImage
    let isSelected: Bool

    @State private var nsImage: NSImage?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.quaternary.opacity(0.3))
                        .frame(height: 140)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)

            // Prompt text
            Text(image.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let path = image.filePath
        DispatchQueue.global(qos: .utility).async {
            // Load at reduced size for performance
            guard let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, nil
            ) else { return }

            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 400,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return
            }

            let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                nsImage = thumbnail
            }
        }
    }
}

// MARK: - Async Image from Disk

/// Helper view to load an image from a file path asynchronously.
private struct AsyncImageFromDisk: View {
    let filePath: String
    var maxHeight: CGFloat = 300
    /// When true, the image expands to fill available space (ignores maxHeight).
    var expandToFill: Bool = false

    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                if expandToFill {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: maxHeight)
                }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.3))
                    .frame(height: expandToFill ? 200 : maxHeight * 0.6)
                    .overlay { ProgressView().scaleEffect(0.7) }
            }
        }
        .onAppear {
            let path = filePath
            DispatchQueue.global(qos: .userInitiated).async {
                if let img = NSImage(contentsOfFile: path) {
                    DispatchQueue.main.async { nsImage = img }
                }
            }
        }
    }
}
