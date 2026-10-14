import CoreGraphics
import Foundation
import BoardKit

/// World-space geometry shared by the renderer and hit testing.
enum CanvasGeometry {
    static let cardCornerRadius: CGFloat = 14
    /// Distance from a card's top edge to its pin center.
    static let pinInset: CGFloat = 10
    static let pinDiameter: CGFloat = 14

    static func radians(_ degrees: Double) -> CGFloat {
        CGFloat(degrees) * .pi / 180
    }

    /// Where strings attach: the pin at the top center of the card, following its rotation.
    static func pinPoint(of card: Card) -> CGPoint {
        let center = CGPoint(x: card.frame.midX, y: card.frame.midY)
        let offset = pinInset - CGFloat(card.frame.height) / 2 // straight up from the center
        let angle = radians(card.rotation)
        return CGPoint(x: center.x - offset * sin(angle), y: center.y + offset * cos(angle))
    }

    /// The axis-aligned box around a card after rotation.
    static func boundingBox(of card: Card) -> CGRect {
        let rect = card.frame.cgRect
        guard card.rotation != 0 else { return rect }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: radians(card.rotation))
            .translatedBy(x: -center.x, y: -center.y)
        return rect.applying(transform)
    }

    /// The box around every card, or `nil` for an empty board.
    static func contentBounds(of cards: [Card]) -> CGRect? {
        cards.reduce(into: CGRect?.none) { bounds, card in
            let box = boundingBox(of: card)
            bounds = bounds?.union(box) ?? box
        }
    }

    /// A cubic Bézier that sags like thread under gravity. Longer strings droop more, up to a
    /// cap. `fan` spreads several strings between the same two cards apart.
    static func stringPath(from a: CGPoint, to b: CGPoint, sag: CGFloat, fan: CGFloat = 0) -> CGPath {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(hypot(dx, dy), 1)
        let droop = min(length * 0.18, 140) * (0.25 + sag) + fan * 18
        let normal = CGVector(dx: -dy / length, dy: dx / length)
        let spread = fan * 12

        let c1 = CGPoint(x: a.x + dx / 3 + normal.dx * spread, y: a.y + dy / 3 + droop + normal.dy * spread)
        let c2 = CGPoint(x: a.x + 2 * dx / 3 + normal.dx * spread, y: a.y + 2 * dy / 3 + droop + normal.dy * spread)

        let path = CGMutablePath()
        path.move(to: a)
        path.addCurve(to: b, control1: c1, control2: c2)
        return path
    }

    /// Offsets that fan out strings sharing the same pair of cards: 0 for a lone string,
    /// then -0.5/0.5, -1/0/1 and so on.
    static func fanOffsets(for strings: [BoardString]) -> [UUID: CGFloat] {
        var groups: [String: [UUID]] = [:]
        for string in strings {
            let ends = [string.from.uuidString, string.to.uuidString].sorted()
            groups[ends.joined(separator: "|"), default: []].append(string.id)
        }
        var offsets: [UUID: CGFloat] = [:]
        for ids in groups.values {
            let middle = CGFloat(ids.count - 1) / 2
            for (index, id) in ids.enumerated() {
                offsets[id] = CGFloat(index) - middle
            }
        }
        return offsets
    }
}
