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
    static let tints = CanvasAppearance.tints
    static let lightTints = CanvasAppearance.lightTints

    /// Night office: deep ink-blue, glass cards catching light, string glowing red.
    static let noir = Theme(
        id: .noir,
        isDark: true,
        canvas: .noir,
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
        canvas: .cork,
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
        canvas: .blueprint,
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
        canvas: .daylight,
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
