import SwiftUI

/// Animated shimmer placeholder shown while an image is being generated.
/// Displays a frosted-glass effect with a moving gradient and status label.
struct ShimmerImagePlaceholder: View {
    @State private var phase: CGFloat = -1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // Base frosted rectangle
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .frame(width: 320, height: 240)

                // Shimmer gradient overlay
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.0),
                            ],
                            startPoint: UnitPoint(x: phase - 0.5, y: 0.5),
                            endPoint: UnitPoint(x: phase + 0.5, y: 0.5)
                        )
                    )
                    .frame(width: 320, height: 240)

                // Center icon + label
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, options: .repeating)

                    Text(String(localized: "creating_your_image", bundle: .appModule))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            .onAppear {
                withAnimation(
                    .linear(duration: 2.0)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 2.0
                }
            }
        }
    }
}
