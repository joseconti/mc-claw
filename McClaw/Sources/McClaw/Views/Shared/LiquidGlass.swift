import SwiftUI

// MARK: - Liquid Glass Modifiers (macOS 26+)

/// Applies Liquid Glass capsule effect on macOS 26+, no-op on older versions.
struct GlassCapsuleModifier: ViewModifier {
    var interactive: Bool = true

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                content.glassEffect(.regular, in: .capsule)
            }
        } else {
            content
        }
    }
}

/// Applies Liquid Glass rounded rectangle effect on macOS 26+, no-op on older versions.
struct GlassRoundedRectModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var interactive: Bool = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
        }
    }
}

/// Applies Liquid Glass circle effect on macOS 26+, no-op on older versions.
struct GlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply Liquid Glass capsule effect (macOS 26+).
    func liquidGlassCapsule(interactive: Bool = true) -> some View {
        modifier(GlassCapsuleModifier(interactive: interactive))
    }

    /// Apply Liquid Glass rounded rectangle effect (macOS 26+).
    func liquidGlass(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        modifier(GlassRoundedRectModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    /// Apply Liquid Glass circle effect (macOS 26+).
    func liquidGlassCircle() -> some View {
        modifier(GlassCircleModifier())
    }
}
