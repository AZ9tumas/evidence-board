import CoreGraphics
import Foundation
import BoardKit

/// World-space geometry shared by the renderer and hit testing.
enum CanvasGeometry {
    static let cardCornerRadius: CGFloat = 14
    /// Distance from a card's top edge to its pin center.
    static let pinInset: CGFloat = 10
    static let pinDiameter: CGFloat = 14

    /// Text and web cards share one radius; photo frames each have their own.
    static func cornerRadius(of card: Card) -> CGFloat {
        if case .image(let image) = card.content { return ImageCardLayout.cardCornerRadius(for: image.frameStyle) }
        return cardCornerRadius
    }

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

    /// `point` in the card's own unrotated space, with the origin at the card's center.
    static func localPoint(_ point: CGPoint, in card: Card) -> CGPoint {
        let dx = point.x - CGFloat(card.frame.midX)
        let dy = point.y - CGFloat(card.frame.midY)
        let angle = -radians(card.rotation)
        return CGPoint(x: dx * cos(angle) - dy * sin(angle), y: dx * sin(angle) + dy * cos(angle))
    }

    /// The inverse of ``localPoint(_:in:)``.
    static func worldPoint(_ local: CGPoint, in card: Card) -> CGPoint {
        let angle = radians(card.rotation)
        return CGPoint(
            x: CGFloat(card.frame.midX) + local.x * cos(angle) - local.y * sin(angle),
            y: CGFloat(card.frame.midY) + local.x * sin(angle) + local.y * cos(angle)
        )
    }

    /// Whether `point` (world space) lies on the card, following its rotation.
    static func contains(_ card: Card, point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        let local = localPoint(point, in: card)
        return abs(local.x) <= CGFloat(card.frame.width) / 2 + tolerance
            && abs(local.y) <= CGFloat(card.frame.height) / 2 + tolerance
    }

    /// The card's frame after dragging `handle` to `point` (world space). The opposite corner
    /// stays put, even on a rotated card.
    static func resizedFrame(
        of card: Card, dragging handle: ResizeHandle, to point: CGPoint,
        minimumSize: CGSize, keepAspectRatio: Bool = false
    ) -> Rect {
        let width = CGFloat(card.frame.width)
        let height = CGFloat(card.frame.height)
        let (sx, sy) = handle.signs
        let fixed = CGPoint(x: -sx * width / 2, y: -sy * height / 2)
        let dragged = localPoint(point, in: card)
        var newWidth = max(minimumSize.width, (dragged.x - fixed.x) * sx)
        var newHeight = max(minimumSize.height, (dragged.y - fixed.y) * sy)
        if keepAspectRatio {
            let factor = max(newWidth / width, newHeight / height)
            newWidth = max(width * factor, minimumSize.width)
            newHeight = max(height * factor, minimumSize.height)
        }
        let center = worldPoint(CGPoint(x: fixed.x + sx * newWidth / 2, y: fixed.y + sy * newHeight / 2), in: card)
        return Rect(x: center.x - newWidth / 2, y: center.y - newHeight / 2, width: newWidth, height: newHeight)
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

/// The corner a resize drag starts from.
enum ResizeHandle: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    /// Which way the corner sits from the card's center: -1 is left or up, 1 is right or down.
    var signs: (CGFloat, CGFloat) {
        switch self {
        case .topLeft: (-1, -1)
        case .topRight: (1, -1)
        case .bottomLeft: (-1, 1)
        case .bottomRight: (1, 1)
        }
    }
}
