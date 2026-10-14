import Foundation

/// A piece of string between two cards' pins.
public struct BoardString: Sendable, Equatable, Identifiable, Codable {
    public static let thicknessRange: ClosedRange<Double> = 1...4
    public static let sagRange: ClosedRange<Double> = 0...1

    public var id: UUID
    public var from: UUID
    public var to: UUID
    public var color: StringColor
    public var thickness: Double
    /// 0 is taut, 1 is loose.
    public var sag: Double
    public var stroke: StringStroke
    public var arrow: StringArrow
    public var label: String?

    public init(
        id: UUID = UUID(),
        from: UUID,
        to: UUID,
        color: StringColor = .tint(.red),
        thickness: Double = 2,
        sag: Double = 0.5,
        stroke: StringStroke = .solid,
        arrow: StringArrow = .none,
        label: String? = nil
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.color = color
        self.thickness = thickness
        self.sag = sag
        self.stroke = stroke
        self.arrow = arrow
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id, from, to, color, thickness, sag, arrow, label
        case stroke = "style"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        from = try c.decode(UUID.self, forKey: .from)
        to = try c.decode(UUID.self, forKey: .to)
        color = try c.decodeIfPresent(StringColor.self, forKey: .color) ?? .tint(.red)
        thickness = try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 2
        sag = try c.decodeIfPresent(Double.self, forKey: .sag) ?? 0.5
        stroke = try c.decodeIfPresent(StringStroke.self, forKey: .stroke) ?? .solid
        arrow = try c.decodeIfPresent(StringArrow.self, forKey: .arrow) ?? StringArrow.none
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }
}

public enum StringStroke: String, Sendable, CaseIterable, DefaultedEnum {
    case solid, dashed, dotted
    public static let unknownValue: StringStroke = .solid
}

public enum StringArrow: String, Sendable, CaseIterable, DefaultedEnum {
    case none, forward, both
    public static let unknownValue: StringArrow = .none
}

/// The eight theme accent colors, each drawn as a two-stop gradient.
public enum Tint: String, Sendable, CaseIterable, Codable {
    case red, amber, lime, teal, azure, violet, rose, graphite
}

/// A string color: a palette name (`"red"`) or an explicit `"#RRGGBB"`.
public enum StringColor: Sendable, Equatable, Codable {
    case tint(Tint)
    case hex(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let tint = Tint(rawValue: raw) {
            self = .tint(tint)
        } else if Self.isHexColor(raw) {
            self = .hex(raw.uppercased())
        } else {
            self = .tint(.red)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .tint(let tint): try c.encode(tint.rawValue)
        case .hex(let hex): try c.encode(hex)
        }
    }

    static func isHexColor(_ s: String) -> Bool {
        s.count == 7 && s.first == "#" && s.dropFirst().allSatisfy(\.isHexDigit)
    }
}
