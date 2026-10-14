import Foundation

/// Reads and writes `.evboard` files (format version 1).
public enum BoardCodec {
    /// Files larger than this are refused before parsing.
    public static let maxFileSize = 2 * 1024 * 1024 * 1024

    /// Parses board JSON, repairing what it can. Anything that had to be dropped or clamped is
    /// listed in the returned ``LoadReport``.
    public static func decode(_ data: Data) throws -> LoadResult {
        guard data.count <= maxFileSize else { throw BoardLoadError.fileTooLarge }

        let file: BoardFile
        do {
            file = try makeDecoder().decode(BoardFile.self, from: data)
        } catch let error as DecodingError {
            throw BoardLoadError.malformed(error.readableDescription)
        } catch {
            throw BoardLoadError.notAnEvidenceBoard
        }

        guard file.format == Board.formatIdentifier else { throw BoardLoadError.notAnEvidenceBoard }
        let version = file.formatVersion ?? Board.currentFormatVersion
        guard version <= Board.currentFormatVersion else { throw BoardLoadError.newerFormat(version) }

        var report = LoadReport()
        report.skippedCards = file.cards?.failures ?? 0
        report.skippedStrings = file.strings?.failures ?? 0
        report.skippedAssets = file.assets?.failures ?? 0

        let createdAt = file.createdAt ?? .unknownTimestamp
        var board = Board(
            id: file.id ?? UUID(),
            title: file.title ?? "Untitled Board",
            createdAt: createdAt,
            modifiedAt: file.modifiedAt ?? createdAt,
            theme: file.theme ?? .system,
            viewport: file.viewport ?? Viewport(),
            cards: file.cards?.elements ?? [],
            strings: file.strings?.elements ?? [],
            assets: file.assets?.values ?? [:]
        )
        BoardValidator.sanitize(&board, report: &report)
        return LoadResult(board: board, report: report)
    }

    /// Serializes a board as pretty-printed JSON with sorted keys, so files diff cleanly.
    /// Assets no card refers to are left out.
    public static func encode(_ board: Board) throws -> Data {
        var board = board
        let referenced = board.referencedAssetIDs
        board.assets = board.assets.filter { referenced.contains($0.key) }
        return try makeEncoder().encode(board)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISO8601.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "'\(string)' is not an ISO-8601 date."
                )
            }
            return date
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.format(date))
        }
        return encoder
    }
}

public struct LoadResult: Sendable {
    public var board: Board
    public var report: LoadReport
}

public enum BoardLoadError: Error, Equatable, LocalizedError {
    case fileTooLarge
    case notAnEvidenceBoard
    case newerFormat(Int)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "This board is too large to open."
        case .notAnEvidenceBoard:
            "This file isn't an Evidence Board."
        case .newerFormat(let version):
            "This board was saved by a newer version of Evidence Board (format \(version))."
        case .malformed(let detail):
            "This board is damaged and can't be opened. \(detail)"
        }
    }
}

// MARK: - Wire format

/// The top level of the file, decoded leniently: every field is optional and the arrays skip
/// elements that fail to decode instead of failing the whole board.
struct BoardFile: Decodable {
    var format: String?
    var formatVersion: Int?
    var id: UUID?
    var title: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var theme: ThemeID?
    var viewport: Viewport?
    var cards: LossyArray<Card>?
    var strings: LossyArray<BoardString>?
    var assets: LossyDictionary<Asset>?
}

extension Board: Encodable {
    enum CodingKeys: String, CodingKey {
        case format, formatVersion, id, title, createdAt, modifiedAt, theme, viewport, cards, strings, assets
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Board.formatIdentifier, forKey: .format)
        try c.encode(Board.currentFormatVersion, forKey: .formatVersion)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(theme, forKey: .theme)
        try c.encode(viewport, forKey: .viewport)
        try c.encode(cards, forKey: .cards)
        try c.encode(strings, forKey: .strings)
        try c.encode(assets, forKey: .assets)
    }
}

// MARK: - Helpers

enum ISO8601 {
    private static let plain = Date.ISO8601FormatStyle()
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func parse(_ string: String) -> Date? {
        (try? plain.parse(string)) ?? (try? fractional.parse(string))
    }

    static func format(_ date: Date) -> String {
        plain.format(date)
    }
}

extension DecodingError {
    var readableDescription: String {
        switch self {
        case .dataCorrupted(let context),
             .keyNotFound(_, let context),
             .typeMismatch(_, let context),
             .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return String(describing: self)
        }
    }
}
