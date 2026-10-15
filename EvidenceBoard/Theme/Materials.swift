import SwiftUI

extension View {
    /// The floating glass used for HUDs and banners: Liquid Glass on macOS 26, a frosted
    /// material with a lit edge before that.
    func glassCapsule() -> some View {
        modifier(GlassBackground(shape: Capsule()))
    }

    /// The same glass in a rounded rectangle, for panels such as the minimap.
    func glassPanel(cornerRadius: CGFloat) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

private struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Reduce Transparency: solid panels with a clear edge (DESIGN.md §14).
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.25), lineWidth: 1) }
        } else {
            glass(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }

    private func frosted(_ content: Content) -> some View {
        let dark = colorScheme == .dark
        return content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: dark
                            ? [.white.opacity(0.18), .white.opacity(0.04)]
                            : [.white.opacity(0.9), .black.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(dark ? 0.35 : 0.12), radius: 12, y: 6)
    }
}
