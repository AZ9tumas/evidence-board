import Foundation

/// Structural theme choices, independent of platform drawing and of the color palette.
public enum BoardTexture: String, Sendable, Hashable, CaseIterable {
    case dots, lines, grain, paper, chalk, ruled, tiles, circuit, linen, newsprint, stars
}

public enum ThemeFont: String, Sendable, Hashable {
    case system, archival, chalk, handwriting, technical, monospaced, casual, editorial, rounded
}

public enum CardEdge: String, Sendable, Hashable {
    case standard, square, rounded, clipped, deckled, ticket
}

public enum CardOrnament: String, Sendable, Hashable {
    case none, archival, chalk, ruled, specimen, circuit, stitching, newspaper, celestial
}

public enum BoardFastener: String, Sendable, Hashable {
    case pushpin, waxSeal, chalkCross, tape, screw, solder, button, paperclip, star
}

public enum PhotoMount: String, Sendable, Hashable {
    case standard, etched, chalk, tape, film, brackets, corners, doubleRule, rounded
}

public enum ConnectionMaterial: String, Sendable, Hashable {
    case thread, cord, chalk, pencil, cable, circuit, twine, ink, orbit

    public var widthScale: Double {
        switch self {
        case .thread: 1
        case .cord: 1.25
        case .chalk: 1.4
        case .pencil: 0.7
        case .cable: 1.15
        case .circuit: 0.9
        case .twine: 1.6
        case .ink: 0.85
        case .orbit: 0.75
        }
    }

    public var hasFibers: Bool { [.thread, .cord, .twine].contains(self) }
    public var hasKnots: Bool { hasFibers || self == .cable }
    public var hasShadow: Bool { hasFibers || self == .cable }
    public var glows: Bool { self == .circuit || self == .orbit }

    /// Extra texture on solid strings; explicit dashed/dotted choices take precedence.
    public var dashPattern: [Double] {
        switch self {
        case .chalk: [5, 1, 2, 1]
        case .pencil: [12, 0.8]
        case .cable: [10, 1]
        case .circuit: [8, 2, 1, 2]
        case .orbit: [2, 4]
        default: []
        }
    }
}

public enum ConnectionLabel: String, Sendable, Hashable {
    case capsule, tag, underline, square, bracket, ticket, plaque, rounded
}

public struct ThemeDesign: Sendable, Hashable {
    public var edge: CardEdge = .standard
    public var cornerRadius: Double = 16
    public var ornament: CardOrnament = .none
    public var font: ThemeFont = .system
    public var fastener: BoardFastener = .pushpin
    public var connection: ConnectionMaterial = .thread
    public var label: ConnectionLabel = .capsule
    public var photoMount: PhotoMount = .standard
    public var borderWidth: Double = 1
    public var shadowOffset: Double = 1
    public var shadowBlur: Double = 1
    public var webMeshOpacity: Double = 1

    public static let standard = ThemeDesign()
}

public extension ThemeID {
    var design: ThemeDesign {
        switch self {
        case .system, .noir, .cork, .blueprint, .daylight: .standard
        case .parchment:
            ThemeDesign(edge: .deckled, cornerRadius: 3, ornament: .archival, font: .archival,
                        fastener: .waxSeal, connection: .cord, label: .tag, photoMount: .etched,
                        borderWidth: 0.8, shadowOffset: 0.6, shadowBlur: 0.7, webMeshOpacity: 0.08)
        case .chalkboard:
            ThemeDesign(edge: .square, cornerRadius: 0, ornament: .chalk, font: .chalk,
                        fastener: .chalkCross, connection: .chalk, label: .underline, photoMount: .chalk,
                        borderWidth: 1.6, shadowOffset: 0, shadowBlur: 0, webMeshOpacity: 0.05)
        case .fieldNotes:
            ThemeDesign(edge: .rounded, cornerRadius: 3, ornament: .ruled, font: .handwriting,
                        fastener: .tape, connection: .pencil, label: .square, photoMount: .tape,
                        borderWidth: 0.6, shadowOffset: 0.4, shadowBlur: 0.4, webMeshOpacity: 0.06)
        case .crimeLab:
            ThemeDesign(edge: .clipped, cornerRadius: 7, ornament: .specimen, font: .technical,
                        fastener: .screw, connection: .cable, label: .bracket, photoMount: .film,
                        borderWidth: 1.2, shadowOffset: 0.2, shadowBlur: 0.25, webMeshOpacity: 0.04)
        case .circuit:
            ThemeDesign(edge: .clipped, cornerRadius: 14, ornament: .circuit, font: .monospaced,
                        fastener: .solder, connection: .circuit, label: .plaque, photoMount: .brackets,
                        borderWidth: 1.3, shadowOffset: 0.1, shadowBlur: 0.8, webMeshOpacity: 0.12)
        case .scrapbook:
            ThemeDesign(edge: .ticket, cornerRadius: 5, ornament: .stitching, font: .casual,
                        fastener: .button, connection: .twine, label: .ticket, photoMount: .corners,
                        borderWidth: 1.1, shadowOffset: 1.25, shadowBlur: 0.65, webMeshOpacity: 0.1)
        case .newsroom:
            ThemeDesign(edge: .square, cornerRadius: 0, ornament: .newspaper, font: .editorial,
                        fastener: .paperclip, connection: .ink, label: .tag, photoMount: .doubleRule,
                        borderWidth: 2, shadowOffset: 0.3, shadowBlur: 0.15, webMeshOpacity: 0)
        case .observatory:
            ThemeDesign(edge: .rounded, cornerRadius: 24, ornament: .celestial, font: .rounded,
                        fastener: .star, connection: .orbit, label: .rounded, photoMount: .rounded,
                        borderWidth: 0.9, shadowOffset: 0.8, shadowBlur: 1.4, webMeshOpacity: 0.15)
        }
    }

    var texture: BoardTexture {
        switch self {
        case .system, .noir, .daylight: .dots
        case .cork: .grain
        case .blueprint: .lines
        case .parchment: .paper
        case .chalkboard: .chalk
        case .fieldNotes: .ruled
        case .crimeLab: .tiles
        case .circuit: .circuit
        case .scrapbook: .linen
        case .newsroom: .newsprint
        case .observatory: .stars
        }
    }
}
