import Foundation

/// Cards on the clipboard, with the strings between them and the assets they use.
public struct BoardClip: Sendable, Equatable, Codable {
    /// Pasteboard type for clips copied between boards.
    public static let pasteboardType = "com.evidenceboard.clip"

    public var cards: [Card]
    public var strings: [BoardString]
    public var assets: [AssetID: Asset]

    public init(cards: [Card], strings: [BoardString] = [], assets: [AssetID: Asset] = [:]) {
        self.cards = cards
        self.strings = strings
        self.assets = assets
    }

    /// The given cards from `board`, the strings that run between two of them, and their assets.
    public init(copying ids: Set<UUID>, from board: Board) {
        cards = board.cards.filter { ids.contains($0.id) }
        strings = board.strings.filter { ids.contains($0.from) && ids.contains($0.to) }
        let used = Board(title: "", createdAt: .unknownTimestamp, modifiedAt: .unknownTimestamp, cards: cards)
            .referencedAssetIDs
        assets = board.assets.filter { used.contains($0.key) }
    }

    /// The box around every card, or `nil` for an empty clip.
    public var bounds: Rect? {
        guard let first = cards.first else { return nil }
        var minX = first.frame.x, minY = first.frame.y
        var maxX = first.frame.x + first.frame.width, maxY = first.frame.y + first.frame.height
        for card in cards.dropFirst() {
            minX = min(minX, card.frame.x)
            minY = min(minY, card.frame.y)
            maxX = max(maxX, card.frame.x + card.frame.width)
            maxY = max(maxY, card.frame.y + card.frame.height)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A copy ready to insert: fresh IDs, moved by (`dx`, `dy`), stacked from `baseZ` upward
    /// in the original order, and stamped with `now`.
    public func instantiated(dx: Double, dy: Double, baseZ: Int, now: Date = .now) -> BoardClip {
        let stamp = now.truncatedToSeconds
        var newIDs: [UUID: UUID] = [:]
        let ordered = cards.enumerated().sorted { ($0.element.z, $0.offset) < ($1.element.z, $1.offset) }
        var copies = cards
        for (rank, entry) in ordered.enumerated() {
            var card = entry.element
            let id = UUID()
            newIDs[card.id] = id
            card.id = id
            card.frame.x += dx
            card.frame.y += dy
            card.z = baseZ + rank
            card.createdAt = stamp
            card.modifiedAt = stamp
            copies[entry.offset] = card
        }
        let strings = strings.compactMap { string -> BoardString? in
            guard let from = newIDs[string.from], let to = newIDs[string.to] else { return nil }
            var copy = string
            copy.id = UUID()
            copy.from = from
            copy.to = to
            return copy
        }
        return BoardClip(cards: copies, strings: strings, assets: assets)
    }

    /// The command that adds this clip to a board.
    public var insertCommand: BoardCommand {
        var commands: [BoardCommand] = []
        if !assets.isEmpty { commands.append(.addAssets(assets)) }
        commands.append(.insertCards(cards))
        if !strings.isEmpty { commands.append(.insertStrings(strings)) }
        return .batch(commands)
    }
}

extension BoardCodec {
    public static func encodeClip(_ clip: BoardClip) throws -> Data {
        try makeEncoder().encode(clip)
    }

    public static func decodeClip(_ data: Data) throws -> BoardClip {
        try makeDecoder().decode(BoardClip.self, from: data)
    }
}
