import SwiftUI
import BoardKit
import CanvasKit

/// A complete set of design tokens. Every theme defines the same tokens, so switching is
/// just swapping values (see DESIGN.md §6).
struct Theme: Sendable {
    let id: ThemeID
    let canvas: CanvasAppearance
    let textPrimary: RGBA
    let textSecondary: RGBA
    let textTertiary: RGBA
    let accentString: GradientPair
    let accentSelect: GradientPair

    /// M0 ships Noir only. Cork, Blueprint and Daylight arrive with M5.
    static func resolve(_ id: ThemeID) -> Theme { .noir }
}

extension Theme {
    static let tints: [Tint: GradientPair] = [
        .red: GradientPair(RGBA(0xFF3B4E), RGBA(0xFF7A59)),
        .amber: GradientPair(RGBA(0xFFB547), RGBA(0xFF8A3D)),
        .lime: GradientPair(RGBA(0xA8E063), RGBA(0x56AB2F)),
        .teal: GradientPair(RGBA(0x2AF5D2), RGBA(0x0BA5A5)),
        .azure: GradientPair(RGBA(0x4FACFE), RGBA(0x3A6BFF)),
        .violet: GradientPair(RGBA(0xA97CFF), RGBA(0x6A3DF0)),
        .rose: GradientPair(RGBA(0xFF7EB3), RGBA(0xE0457B)),
        .graphite: GradientPair(RGBA(0xB8C0D6), RGBA(0x7D86A0)),
    ]

    /// Night office: deep ink-blue, glass cards catching light, string glowing red.
    static let noir = Theme(
        id: .noir,
        canvas: CanvasAppearance(
            background: GradientPair(RGBA(0x0B0E17), RGBA(0x151A2C)),
            vignette: RGBA.black.opacity(0.45),
            gridDot: RGBA.white.opacity(0.06),
            cardFill: GradientPair(RGBA(0x1B2133), RGBA(0x141927)),
            cardStroke: GradientPair(RGBA.white.opacity(0.14), RGBA.white.opacity(0.03)),
            skeleton: RGBA.white.opacity(0.06),
            pin: GradientPair(RGBA(0xFF4757), RGBA(0xB3121F)),
            lockedPin: GradientPair(RGBA(0xE9C46A), RGBA(0xA6802B)),
            tints: Theme.tints,
            text: RGBA(0xF2F4FA),
            codeText: RGBA(0x7FE7D3),
            paperFill: GradientPair(RGBA(0x2B2822), RGBA(0x211E1A)),
            paperText: RGBA(0xEDE4D3),
            selection: GradientPair(RGBA(0x5B8CFF), RGBA(0x9B6BFF)),
            photoPaper: GradientPair(RGBA(0xF6F3EC), RGBA(0xE6E0D4)),
            captionInk: RGBA(0x34302A),
            labelFill: GradientPair(RGBA(0x2A3046, alpha: 0.88), RGBA(0x1A1E2E, alpha: 0.88)),
            labelText: RGBA(0xF2F4FA)
        ),
        textPrimary: RGBA(0xF2F4FA),
        textSecondary: RGBA(0xA7AEC2),
        textTertiary: RGBA(0x6B7390),
        accentString: Theme.tints[.red]!,
        accentSelect: GradientPair(RGBA(0x5B8CFF), RGBA(0x9B6BFF))
    )
}

extension RGBA {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension GradientPair {
    func linear(_ start: UnitPoint = .topLeading, _ end: UnitPoint = .bottomTrailing) -> LinearGradient {
        LinearGradient(colors: [from.color, to.color], startPoint: start, endPoint: end)
    }
}
