import Foundation

/// Key into ``Board/assets``: `sha256-` followed by the hex digest of the raw bytes.
public typealias AssetID = String

public enum CardKind: String, Sendable, CaseIterable {
    case text, image, web
}

/// One item pinned to the board. A card is always exactly one of text, image or web.
public struct Card: Sendable, Equatable, Identifiable {
    public static let rotationRange: ClosedRange<Double> = -15...15

    public var id: UUID
    /// World-space frame, top-left origin, y grows downward.
    public var frame: Rect
    /// Degrees, positive is clockwise.
    public var rotation: Double
    /// Stacking order, higher is in front.
    public var z: Int
    public var tint: Tint?
    public var locked: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var content: CardContent

    public init(
        id: UUID = UUID(),
        frame: Rect,
        rotation: Double = 0,
        z: Int = 0,
        tint: Tint? = nil,
        locked: Bool = false,
        createdAt: Date,
        modifiedAt: Date,
        content: CardContent
    ) {
        self.id = id
        self.frame = frame
        self.rotation = rotation
        self.z = z
        self.tint = tint
        self.locked = locked
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.content = content
    }

    public var kind: CardKind { content.kind }
}

public enum CardContent: Sendable, Equatable {
    case text(TextPayload)
    case image(ImagePayload)
    case web(WebPayload)

    public var kind: CardKind {
        switch self {
        case .text: .text
        case .image: .image
        case .web: .web
        }
    }
}

/// A plain rectangle with the JSON shape `{ "x", "y", "width", "height" }`.
public struct Rect: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

#if canImport(CoreGraphics)
import CoreGraphics

extension Rect {
    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
#endif

// MARK: - Codable

extension Card: Codable {
    enum CodingKeys: String, CodingKey {
        case id, type, frame, rotation, z, tint, locked, createdAt, modifiedAt, text, image, web
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        frame = try c.decode(Rect.self, forKey: .frame)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        z = try c.decodeIfPresent(Int.self, forKey: .z) ?? 0
        tint = try c.decodeIfPresent(String.self, forKey: .tint).flatMap(Tint.init(rawValue:))
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .unknownTimestamp
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt

        let type = try c.decode(String.self, forKey: .type)
        switch CardKind(rawValue: type) {
        case .text:
            content = .text(try c.decode(TextPayload.self, forKey: .text))
        case .image:
            content = .image(try c.decode(ImagePayload.self, forKey: .image))
        case .web:
            content = .web(try c.decode(WebPayload.self, forKey: .web))
        case nil:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unsupported card type '\(type)'. Only text, image and web are allowed."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .type)
        try c.encode(frame, forKey: .frame)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(z, forKey: .z)
        try c.encodeIfPresent(tint, forKey: .tint)
        try c.encode(locked, forKey: .locked)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        switch content {
        case .text(let payload): try c.encode(payload, forKey: .text)
        case .image(let payload): try c.encode(payload, forKey: .image)
        case .web(let payload): try c.encode(payload, forKey: .web)
        }
    }
}

extension Date {
    /// Used when a hand-written file leaves out a card's timestamps.
    static let unknownTimestamp = Date(timeIntervalSince1970: 0)
}
