import Foundation

/// What had to be repaired while loading a board.
public struct LoadReport: Sendable, Equatable {
    public var skippedCards = 0
    public var skippedStrings = 0
    public var skippedAssets = 0
    /// Out-of-range numbers that were clamped (zoom, rotation, sizes, string thickness and sag).
    public var adjustedValues = 0

    public init() {}

    public var skippedItems: Int { skippedCards + skippedStrings }

    /// A one-line message for the non-blocking banner, or `nil` if nothing was lost.
    public var summary: String? {
        switch skippedItems {
        case 0: nil
        case 1: "1 item couldn't be loaded."
        default: "\(skippedItems) items couldn't be loaded."
        }
    }
}

/// Repairs a freshly decoded board so the rest of the app can trust it.
enum BoardValidator {
    static let maxCards = 100_000
    static let coordinateRange: ClosedRange<Double> = -10_000_000...10_000_000
    static let sizeRange: ClosedRange<Double> = 1...100_000

    static func sanitize(_ board: inout Board, report: inout LoadReport) {
        clamp(&board.viewport.x, to: coordinateRange, report: &report)
        clamp(&board.viewport.y, to: coordinateRange, report: &report)
        clamp(&board.viewport.zoom, to: Viewport.zoomRange, report: &report)

        var cardIDs = Set<UUID>()
        var cards: [Card] = []
        cards.reserveCapacity(min(board.cards.count, maxCards))
        for var card in board.cards {
            guard cards.count < maxCards else {
                report.skippedCards += 1
                continue
            }
            if case .web(let web) = card.content, !web.url.isWebURL {
                report.skippedCards += 1
                continue
            }
            guard cardIDs.insert(card.id).inserted else {
                report.skippedCards += 1
                continue
            }
            clamp(&card.rotation, to: Card.rotationRange, report: &report)
            clamp(&card.frame.x, to: coordinateRange, report: &report)
            clamp(&card.frame.y, to: coordinateRange, report: &report)
            clamp(&card.frame.width, to: sizeRange, report: &report)
            clamp(&card.frame.height, to: sizeRange, report: &report)
            cards.append(card)
        }
        board.cards = cards

        var stringIDs = Set<UUID>()
        var strings: [BoardString] = []
        strings.reserveCapacity(board.strings.count)
        for var string in board.strings {
            let isValid = string.from != string.to
                && cardIDs.contains(string.from)
                && cardIDs.contains(string.to)
                && stringIDs.insert(string.id).inserted
            guard isValid else {
                report.skippedStrings += 1
                continue
            }
            clamp(&string.thickness, to: BoardString.thicknessRange, report: &report)
            clamp(&string.sag, to: BoardString.sagRange, report: &report)
            strings.append(string)
        }
        board.strings = strings
    }

    private static func clamp(_ value: inout Double, to range: ClosedRange<Double>, report: inout LoadReport) {
        let clamped = value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
        if clamped != value {
            value = clamped
            report.adjustedValues += 1
        }
    }
}

extension URL {
    /// Only `http` and `https` links may become web cards.
    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return host()?.isEmpty == false
    }
}
