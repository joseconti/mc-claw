import SwiftUI

/// Capsule pill selector for Git platforms (GitHub / GitLab), matching the CLI selector style.
struct GitPlatformSelector: View {
    @Binding var selectedPlatform: GitPlatform
    let availablePlatforms: [GitPlatform]

    @Namespace private var platformNamespace

    var body: some View {
        if availablePlatforms.count > 1 {
            HStack(spacing: 0) {
                ForEach(availablePlatforms) { platform in
                    let isSelected = platform == selectedPlatform
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            selectedPlatform = platform
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: platform.icon)
                                .font(.caption2)
                            Text(platform.displayName)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        }
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.35))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "platformPill", in: platformNamespace)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
            .liquidGlassCapsule()
        } else if let platform = availablePlatforms.first {
            HStack(spacing: 4) {
                Image(systemName: platform.icon)
                    .font(.caption2)
                Text(platform.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
        }
    }
}
