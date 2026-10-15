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
    static let maxStrings = 500_000
    static let maxAssets = 100_000
    /// Longest text a card keeps, in characters. Longer text is cut (DESIGN.md §13).
    static let maxTextLength = 1_000_000
    /// Longest title, caption, label or link field.
    static let maxShortTextLength = 10_000
    static let maxMediaDuration: Double = 10_000_000
    static let coordinateRange: ClosedRange<Double> = -10_000_000...10_000_000
    static let sizeRange: ClosedRange<Double> = 1...100_000

    static func sanitize(_ board: inout Board, report: inout LoadReport) {
        limit(&board.title, to: maxShortTextLength, report: &report)
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
            sanitize(&card.content, report: &report)
            cards.append(card)
        }
        board.cards = cards

        var stringIDs = Set<UUID>()
        var strings: [BoardString] = []
        strings.reserveCapacity(board.strings.count)
        for var string in board.strings {
            let isValid = strings.count < maxStrings
                && string.from != string.to
                && cardIDs.contains(string.from)
                && cardIDs.contains(string.to)
                && stringIDs.insert(string.id).inserted
            guard isValid else {
                report.skippedStrings += 1
                continue
            }
            clamp(&string.thickness, to: BoardString.thicknessRange, report: &report)
            clamp(&string.sag, to: BoardString.sagRange, report: &report)
            if var label = string.label {
                limit(&label, to: maxShortTextLength, report: &report)
                string.label = label
            }
            strings.append(string)
        }
        board.strings = strings

        if board.assets.count > maxAssets {
            let kept = Set(board.assets.keys.sorted().prefix(maxAssets))
            report.skippedAssets += board.assets.count - kept.count
            board.assets = board.assets.filter { kept.contains($0.key) }
        }
    }

    /// Caps text lengths and repairs numbers inside a card's content: a photo's crop and a
    /// video's duration.
    private static func sanitize(_ content: inout CardContent, report: inout LoadReport) {
        switch content {
        case .text(var text):
            limit(&text.content, to: maxTextLength, report: &report)
            content = .text(text)
        case .image(var image):
            if var caption = image.caption {
                limit(&caption, to: maxShortTextLength, report: &report)
                image.caption = caption
            }
            if let crop = image.crop {
                let repaired = repairedCrop(crop)
                if repaired != crop {
                    image.crop = repaired
                    report.adjustedValues += 1
                }
            }
            content = .image(image)
        case .web(var web):
            guard var snapshot = web.snapshot else { return }
            for keyPath in [\LinkSnapshot.title, \.pageDescription, \.siteName, \.author] {
                if var value = snapshot[keyPath: keyPath] {
                    limit(&value, to: maxShortTextLength, report: &report)
                    snapshot[keyPath: keyPath] = value
                }
            }
            if let duration = snapshot.mediaDuration, !(duration.isFinite && duration >= 0 && duration <= maxMediaDuration) {
                snapshot.mediaDuration = nil
                report.adjustedValues += 1
            }
            web.snapshot = snapshot
            content = .web(web)
        }
    }

    /// A crop is a normalized rect inside the photo. Anything else is dropped (`nil` shows
    /// the whole photo) or pulled back inside.
    static func repairedCrop(_ crop: Rect) -> Rect? {
        let values = [crop.x, crop.y, crop.width, crop.height]
        guard values.allSatisfy(\.isFinite), crop.width > 0, crop.height > 0 else { return nil }
        let width = min(max(crop.width, 0.01), 1)
        let height = min(max(crop.height, 0.01), 1)
        return Rect(
            x: min(max(crop.x, 0), 1 - width),
            y: min(max(crop.y, 0), 1 - height),
            width: width,
            height: height
        )
    }

    private static func limit(_ text: inout String, to length: Int, report: inout LoadReport) {
        // utf8.count is O(1) for native strings, so short text costs nothing to check.
        guard text.utf8.count > length, text.count > length else { return }
        text = String(text.prefix(length))
        report.adjustedValues += 1
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
