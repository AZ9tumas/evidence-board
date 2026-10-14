import Foundation

/// A whole evidence board: everything that ends up in one `.evboard` file.
public struct Board: Sendable, Equatable {
    /// Magic value of the top-level `format` key.
    public static let formatIdentifier = "evidenceboard"
    /// The format version this build reads and writes.
    public static let currentFormatVersion = 1

    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var theme: ThemeID
    public var viewport: Viewport
    public var cards: [Card]
    public var strings: [BoardString]
    public var assets: [AssetID: Asset]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date,
        modifiedAt: Date,
        theme: ThemeID = .system,
        viewport: Viewport = Viewport(),
        cards: [Card] = [],
        strings: [BoardString] = [],
        assets: [AssetID: Asset] = [:]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.theme = theme
        self.viewport = viewport
        self.cards = cards
        self.strings = strings
        self.assets = assets
    }

    /// A fresh, empty board. Timestamps are whole seconds so they survive a save/load round trip.
    public static func new(title: String = "Untitled Board", now: Date = .now) -> Board {
        let stamp = now.truncatedToSeconds
        return Board(title: title, createdAt: stamp, modifiedAt: stamp)
    }

    /// Asset IDs that at least one card uses. Everything else is dropped on save.
    public var referencedAssetIDs: Set<AssetID> {
        var ids = Set<AssetID>()
        for card in cards {
            switch card.content {
            case .text:
                break
            case .image(let image):
                ids.insert(image.asset)
            case .web(let web):
                if let image = web.snapshot?.image { ids.insert(image) }
                if let icon = web.snapshot?.icon { ids.insert(icon) }
            }
        }
        return ids
    }
}

/// The camera position saved with a board: the world point at the window center, and the zoom.
public struct Viewport: Sendable, Equatable, Codable {
    public static let zoomRange: ClosedRange<Double> = 0.05...8

    public var x: Double
    public var y: Double
    public var zoom: Double

    public init(x: Double = 0, y: Double = 0, zoom: Double = 1) {
        self.x = x
        self.y = y
        self.zoom = zoom
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        zoom = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
    }
}

public enum ThemeID: String, Sendable, CaseIterable, DefaultedEnum {
    case system, noir, cork, blueprint, daylight
    public static let unknownValue: ThemeID = .system
}

extension Date {
    var truncatedToSeconds: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
