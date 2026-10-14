import CoreGraphics
import BoardKit

/// An sRGB color that is cheap to store, compare and send across actors.
public struct RGBA: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `RGBA(0xFF3B4E)`
    public init(_ hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// `RGBA(hex: "#FF3B4E")`, or `nil` if the string isn't `#RRGGBB`.
    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(value)
    }

    public static let white = RGBA(0xFFFFFF)
    public static let black = RGBA(0x000000)
    public static let clear = RGBA(0x000000, alpha: 0)

    public func opacity(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// A two-stop gradient.
public struct GradientPair: Sendable, Hashable {
    public var from: RGBA
    public var to: RGBA

    public init(_ from: RGBA, _ to: RGBA) {
        self.from = from
        self.to = to
    }

    var cgColors: [CGColor] { [from.cgColor, to.cgColor] }
}

/// The color tokens the canvas draws with. The app builds one from its active theme.
public struct CanvasAppearance: Sendable, Hashable {
    public var background: GradientPair
    public var vignette: RGBA
    public var gridDot: RGBA
    public var cardFill: GradientPair
    public var cardStroke: GradientPair
    public var skeleton: RGBA
    public var pin: GradientPair
    public var lockedPin: GradientPair
    public var tints: [Tint: GradientPair]

    public init(
        background: GradientPair,
        vignette: RGBA,
        gridDot: RGBA,
        cardFill: GradientPair,
        cardStroke: GradientPair,
        skeleton: RGBA,
        pin: GradientPair,
        lockedPin: GradientPair,
        tints: [Tint: GradientPair]
    ) {
        self.background = background
        self.vignette = vignette
        self.gridDot = gridDot
        self.cardFill = cardFill
        self.cardStroke = cardStroke
        self.skeleton = skeleton
        self.pin = pin
        self.lockedPin = lockedPin
        self.tints = tints
    }

    func gradient(for tint: Tint) -> GradientPair {
        tints[tint] ?? pin
    }

    func gradient(for color: StringColor) -> GradientPair {
        switch color {
        case .tint(let tint):
            return gradient(for: tint)
        case .hex(let hex):
            let rgba = RGBA(hex: hex) ?? pin.from
            return GradientPair(rgba, rgba)
        }
    }
}
