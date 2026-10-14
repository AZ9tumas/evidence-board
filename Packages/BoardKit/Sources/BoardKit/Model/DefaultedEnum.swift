/// A string enum that decodes unknown raw values to a fallback instead of failing.
///
/// Boards may be written by hand, by scripts or by newer versions of the app, so an
/// unrecognised style name must not make the whole file unreadable.
/// `unknownValue` is what any unrecognized raw value decodes to.
public protocol DefaultedEnum: RawRepresentable, Codable, Sendable where RawValue == String {
    static var unknownValue: Self { get }
}

extension DefaultedEnum {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknownValue
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
