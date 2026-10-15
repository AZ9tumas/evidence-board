import SwiftUI
import BoardKit
import CanvasKit

/// A complete set of design tokens. Every theme defines the same tokens, so switching is
/// just swapping values (see DESIGN.md §6).
struct Theme: Sendable {
    let id: ThemeID
    let isDark: Bool
    let canvas: CanvasAppearance
    let textPrimary: RGBA
    let textSecondary: RGBA
    let textTertiary: RGBA
    let accentString: GradientPair
    let accentSelect: GradientPair

    /// The theme a board shows. Automatic follows the Mac: Noir when it's dark, Daylight
    /// when it's light (§6.2).
    static func resolve(_ id: ThemeID, systemIsDark: Bool) -> Theme {
        switch id {
        case .system: systemIsDark ? .noir : .daylight
        case .noir: .noir
        case .cork: .cork
        case .blueprint: .blueprint
        case .daylight: .daylight
        }
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

extension ThemeID {
    var title: String {
        switch self {
        case .system: "Automatic"
        case .noir: "Noir"
        case .cork: "Cork"
        case .blueprint: "Blueprint"
        case .daylight: "Daylight"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "Noir in Dark Mode, Daylight in Light Mode"
        case .noir: "Night office"
        case .cork: "Classic corkboard"
        case .blueprint: "Engineering drawing"
        case .daylight: "Light and airy"
        }
    }
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

    /// The same hues a little deeper, so they hold up on paper and light cards.
    static let lightTints: [Tint: GradientPair] = [
        .red: GradientPair(RGBA(0xF0384A), RGBA(0xF26A4B)),
        .amber: GradientPair(RGBA(0xF5A524), RGBA(0xF07A28)),
        .lime: GradientPair(RGBA(0x86C440), RGBA(0x3F9425)),
        .teal: GradientPair(RGBA(0x16CDB0), RGBA(0x078A8A)),
        .azure: GradientPair(RGBA(0x3A9AF2), RGBA(0x2F5CF0)),
        .violet: GradientPair(RGBA(0x9466F5), RGBA(0x5B2FE0)),
        .rose: GradientPair(RGBA(0xF56AA2), RGBA(0xD3386E)),
        .graphite: GradientPair(RGBA(0x98A1B8), RGBA(0x667089)),
    ]

    /// Night office: deep ink-blue, glass cards catching light, string glowing red.
    static let noir = Theme(
        id: .noir,
        isDark: true,
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

    /// The classic corkboard: warm cork grain, paper cards, deep red wool.
    static let cork = Theme(
        id: .cork,
        isDark: true,
        canvas: CanvasAppearance(
            background: GradientPair(RGBA(0x8A6440), RGBA(0x5E3F22)),
            vignette: RGBA(0x24140A, alpha: 0.55),
            gridDot: RGBA(0x2E1A0B, alpha: 0.9),
            cardFill: GradientPair(RGBA(0xFCF9F1), RGBA(0xF1EADB)),
            cardStroke: GradientPair(RGBA.white.opacity(0.9), RGBA(0x5E3F22, alpha: 0.12)),
            skeleton: RGBA(0x3B2A1A, alpha: 0.08),
            pin: GradientPair(RGBA(0xE8333F), RGBA(0x8E1420)),
            lockedPin: GradientPair(RGBA(0xE9C46A), RGBA(0xA6802B)),
            tints: Theme.lightTints,
            text: RGBA(0x2A2118),
            codeText: RGBA(0xA4401F),
            paperFill: GradientPair(RGBA(0xF4E7C5), RGBA(0xE9D6A8)),
            paperText: RGBA(0x3A2C1A),
            selection: GradientPair(RGBA(0x2F6BFF), RGBA(0x7B4DFF)),
            photoPaper: GradientPair(RGBA(0xFFFFFF), RGBA(0xF1ECE2)),
            captionInk: RGBA(0x34302A),
            labelFill: GradientPair(RGBA(0xFFFAEE, alpha: 0.96), RGBA(0xF1E7D3, alpha: 0.96)),
            labelText: RGBA(0x3A2C1A),
            texture: .grain,
            shadow: RGBA(0x2B1406, alpha: 1),
            string: GradientPair(RGBA(0xC81D2B), RGBA(0x9A1622))
        ),
        textPrimary: RGBA(0xFFF6E8),
        textSecondary: RGBA(0xE9D7BD),
        textTertiary: RGBA(0xC2A684),
        accentString: GradientPair(RGBA(0xE8333F), RGBA(0xB3121F)),
        accentSelect: GradientPair(RGBA(0x2F6BFF), RGBA(0x7B4DFF))
    )

    /// Engineering drawing: blueprint blue with a drafting grid, glass cards, white thread.
    static let blueprint = Theme(
        id: .blueprint,
        isDark: true,
        canvas: CanvasAppearance(
            background: GradientPair(RGBA(0x0F4373), RGBA(0x08284A)),
            vignette: RGBA(0x021327, alpha: 0.5),
            gridDot: RGBA(0xBFE3FF, alpha: 0.09),
            cardFill: GradientPair(RGBA(0x1C578F, alpha: 0.78), RGBA(0x124171, alpha: 0.78)),
            cardStroke: GradientPair(RGBA(0xA9DBFF, alpha: 0.55), RGBA(0xA9DBFF, alpha: 0.1)),
            skeleton: RGBA.white.opacity(0.08),
            pin: GradientPair(RGBA(0xFFFFFF), RGBA(0x86C3EE)),
            lockedPin: GradientPair(RGBA(0xE9C46A), RGBA(0xA6802B)),
            tints: Theme.tints,
            text: RGBA(0xF2F8FF),
            codeText: RGBA(0x8FE3FF),
            paperFill: GradientPair(RGBA(0xE9F1F8, alpha: 0.95), RGBA(0xD6E3EE, alpha: 0.95)),
            paperText: RGBA(0x15324F),
            selection: GradientPair(RGBA(0x6FE0FF), RGBA(0xB49BFF)),
            photoPaper: GradientPair(RGBA(0xF4F8FC), RGBA(0xDCE6F0)),
            captionInk: RGBA(0x1A2B3D),
            labelFill: GradientPair(RGBA(0x10406C, alpha: 0.92), RGBA(0x0A3058, alpha: 0.92)),
            labelText: RGBA(0xEAF4FF),
            texture: .lines,
            shadow: RGBA(0x01101F, alpha: 0.95),
            string: GradientPair(RGBA(0xFFFFFF), RGBA(0x8FE3FF))
        ),
        textPrimary: RGBA(0xEAF4FF),
        textSecondary: RGBA(0xA9C6E3),
        textTertiary: RGBA(0x6F93B8),
        accentString: GradientPair(RGBA(0xFFFFFF), RGBA(0x8FE3FF)),
        accentSelect: GradientPair(RGBA(0x6FE0FF), RGBA(0xB49BFF))
    )

    /// Light mode: soft daylight grays, white cards with a hairline, red a little quieter.
    static let daylight = Theme(
        id: .daylight,
        isDark: false,
        canvas: CanvasAppearance(
            background: GradientPair(RGBA(0xF5F6FA), RGBA(0xE4E8F2)),
            vignette: RGBA(0x7D88A6, alpha: 0.14),
            gridDot: RGBA(0x1B2440, alpha: 0.10),
            cardFill: GradientPair(RGBA(0xFFFFFF), RGBA(0xF9FAFC)),
            cardStroke: GradientPair(RGBA(0x1B2440, alpha: 0.12), RGBA(0x1B2440, alpha: 0.07)),
            skeleton: RGBA(0x1B2440, alpha: 0.06),
            pin: GradientPair(RGBA(0xFF4757), RGBA(0xC81E2C)),
            lockedPin: GradientPair(RGBA(0xE9C46A), RGBA(0xA6802B)),
            tints: Theme.lightTints,
            text: RGBA(0x1B1F2A),
            codeText: RGBA(0x0A7D6E),
            paperFill: GradientPair(RGBA(0xFFF8E6), RGBA(0xF6EBCD)),
            paperText: RGBA(0x3A3122),
            selection: GradientPair(RGBA(0x3A6BFF), RGBA(0x8A4DFF)),
            photoPaper: GradientPair(RGBA(0xFFFFFF), RGBA(0xF3F1EC)),
            captionInk: RGBA(0x34302A),
            labelFill: GradientPair(RGBA(0xFFFFFF, alpha: 0.96), RGBA(0xF2F4F8, alpha: 0.96)),
            labelText: RGBA(0x1B1F2A),
            texture: .dots,
            shadow: RGBA(0x1A2340, alpha: 0.5),
            string: GradientPair(RGBA(0xE5484D), RGBA(0xEC7A5F))
        ),
        textPrimary: RGBA(0x1B1F2A),
        textSecondary: RGBA(0x5B6478),
        textTertiary: RGBA(0x8C93A6),
        accentString: GradientPair(RGBA(0xE5484D), RGBA(0xEC7A5F)),
        accentSelect: GradientPair(RGBA(0x3A6BFF), RGBA(0x8A4DFF))
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
