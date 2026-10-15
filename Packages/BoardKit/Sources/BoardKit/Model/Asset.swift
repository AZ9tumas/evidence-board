import Foundation

/// A binary blob (image, link thumbnail, favicon) embedded in the board file.
///
/// The bytes stay base64-encoded in memory until something needs to draw them, so opening a
/// large board doesn't pay for decoding images that are off screen.
public struct Asset: Sendable, Equatable, Codable {
    public var mime: String
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var byteCount: Int?
    public var base64: String

    public init(mime: String, pixelWidth: Int? = nil, pixelHeight: Int? = nil, data: Data) {
        self.mime = mime
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = data.count
        var base64 = data.base64EncodedString()
        base64.makeContiguousUTF8()
        self.base64 = base64
    }

    /// The raw bytes, or `nil` if the base64 is corrupt.
    public func decodedData() -> Data? {
        Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    enum CodingKeys: String, CodingKey {
        case mime, pixelWidth, pixelHeight, byteCount
        case base64 = "data"
    }
}
