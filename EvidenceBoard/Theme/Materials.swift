import SwiftUI

extension View {
    /// The floating glass used for HUDs and banners: Liquid Glass on macOS 26, a frosted
    /// material with a lit edge before that.
    @ViewBuilder
    func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            frostedCapsule()
        }
        #else
        frostedCapsule()
        #endif
    }

    private func frostedCapsule() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}
