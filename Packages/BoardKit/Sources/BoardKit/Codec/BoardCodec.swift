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
    ///
    /// Image data is most of a big board, and it's plain base64 that needs no escaping. So the
    /// encoder writes a short placeholder for each large asset and the bytes are copied in
    /// afterwards, which is many times faster than escaping megabytes of text (DESIGN.md §11).
    /// The result is byte for byte what the encoder alone would write.
    public static func encode(_ board: Board) throws -> Data {
        var board = referencedOnly(board)
        let token = "@@evboard-asset-\(UUID().uuidString)-"
        var payloads: [String] = []
        for id in board.assets.keys.sorted() {
            guard var base64 = board.assets[id]?.base64 else { continue }
            // Foundation may hand back bridged strings; native UTF-8 makes the checks and copies
            // below memory-speed.
            base64.makeContiguousUTF8()
            guard base64.utf8.count >= 4096, isPlainBase64(base64) else { continue }
            board.assets[id]?.base64 = token + String(payloads.count) + "@@"
            payloads.append(base64)
        }
        let skeleton = try makeEncoder().encode(board)
        return payloads.isEmpty ? skeleton : splice(payloads, into: skeleton, at: Array(token.utf8))
    }

    /// What ``encode(_:)`` writes, made by the encoder alone. For tests.
    static func encodeDirectly(_ board: Board) throws -> Data {
        try makeEncoder().encode(referencedOnly(board))
    }

    private static func referencedOnly(_ board: Board) -> Board {
        var board = board
        let referenced = board.referencedAssetIDs
        board.assets = board.assets.filter { referenced.contains($0.key) }
        return board
    }

    private static let base64Alphabet: [Bool] = {
        var table = [Bool](repeating: false, count: 256)
        let ranges: [ClosedRange<UInt8>] = [UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9")]
        for range in ranges {
            for byte in range { table[Int(byte)] = true }
        }
        for byte in [UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "=")] { table[Int(byte)] = true }
        return table
    }()

    /// Only base64 characters, so it can go into JSON as is.
    static func isPlainBase64(_ text: String) -> Bool {
        let alphabet = base64Alphabet
        if let result = text.utf8.withContiguousStorageIfAvailable({ bytes in bytes.allSatisfy { alphabet[Int($0)] } }) {
            return result
        }
        return text.utf8.allSatisfy { alphabet[Int($0)] }
    }

    /// Replaces each `token` + index + `@@` in `skeleton` with that payload.
    private static func splice(_ payloads: [String], into skeleton: Data, at token: [UInt8]) -> Data {
        var output = Data(capacity: skeleton.count + payloads.reduce(0) { $0 + $1.utf8.count })
        skeleton.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let at = UInt8(ascii: "@")
            var copied = 0
            var index = 0
            while index + token.count <= bytes.count {
                guard bytes[index] == token[0], bytes[index..<index + token.count].elementsEqual(token) else {
                    index += 1
                    continue
                }
                var end = index + token.count
                var number = 0
                while end < bytes.count, bytes[end] != at {
                    number = number * 10 + Int(bytes[end] &- UInt8(ascii: "0"))
                    end += 1
                }
                output.append(UnsafeBufferPointer(rebasing: bytes[copied..<index]))
                let payload = payloads[number]
                if payload.utf8.withContiguousStorageIfAvailable({ output.append($0) }) == nil {
                    output.append(contentsOf: Array(payload.utf8))
                }
                index = end + 2 // past "@@"
                copied = index
            }
            output.append(UnsafeBufferPointer(rebasing: bytes[copied...]))
        }
        return output
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
