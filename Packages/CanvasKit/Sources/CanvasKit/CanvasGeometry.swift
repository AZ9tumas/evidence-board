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
    /// cap. `fan` spreads several strings between the same two cards apart, and `droopScale`
    /// lets the "pull taut" animation overshoot the resting sag.
    static func stringCurve(
        from a: CGPoint, to b: CGPoint, sag: CGFloat, fan: CGFloat = 0, droopScale: CGFloat = 1
    ) -> StringCurve {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(hypot(dx, dy), 1)
        let droop = droopCap(length) * (0.25 + sag) * droopScale + fan * 18
        let normal = CGVector(dx: -dy / length, dy: dx / length)
        let spread = fan * 12
        return StringCurve(
            a: a,
            c1: CGPoint(x: a.x + dx / 3 + normal.dx * spread, y: a.y + dy / 3 + droop + normal.dy * spread),
            c2: CGPoint(x: a.x + 2 * dx / 3 + normal.dx * spread, y: a.y + 2 * dy / 3 + droop + normal.dy * spread),
            b: b
        )
    }

    static func stringPath(from a: CGPoint, to b: CGPoint, sag: CGFloat, fan: CGFloat = 0) -> CGPath {
        stringCurve(from: a, to: b, sag: sag, fan: fan).path
    }

    /// How far a string of `length` droops per unit of `0.25 + sag`.
    static func droopCap(_ length: CGFloat) -> CGFloat {
        min(length * 0.18, 140)
    }

    /// The sag after dragging a string's middle down by `dy` (world space). The middle of the
    /// curve sits 0.75 × droop below the chord, so that's the rate it follows the pointer.
    static func sag(_ sag: CGFloat, afterDragging dy: CGFloat, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let rate = 0.75 * max(droopCap(hypot(b.x - a.x, b.y - a.y)), 1)
        return min(max(sag + dy / rate, 0), 1)
    }

    /// The distance from `point` to the nearest point of a polyline.
    static func distance(from point: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        guard var previous = polyline.first else { return .infinity }
        var best = hypot(point.x - previous.x, point.y - previous.y)
        for next in polyline.dropFirst() {
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0
                ? min(max(((point.x - previous.x) * dx + (point.y - previous.y) * dy) / lengthSquared, 0), 1)
                : 0
            best = min(best, hypot(point.x - (previous.x + t * dx), point.y - (previous.y + t * dy)))
            previous = next
        }
        return best
    }

    static func length(of polyline: [CGPoint]) -> CGFloat {
        zip(polyline, polyline.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// The point `distance` back from the last point of a polyline, and the unit direction
    /// pointing toward the end there. Used to place arrowheads just clear of a pin.
    static func point(on polyline: [CGPoint], distanceFromEnd distance: CGFloat) -> (point: CGPoint, direction: CGVector)? {
        guard polyline.count >= 2 else { return nil }
        var remaining = distance
        var index = polyline.count - 1
        while index > 0 {
            let end = polyline[index]
            let start = polyline[index - 1]
            let segment = hypot(end.x - start.x, end.y - start.y)
            if segment > 0 && (remaining <= segment || index == 1) {
                let t = min(remaining / segment, 1)
                let direction = CGVector(dx: (end.x - start.x) / segment, dy: (end.y - start.y) / segment)
                return (CGPoint(x: end.x - direction.dx * t * segment, y: end.y - direction.dy * t * segment), direction)
            }
            remaining -= segment
            index -= 1
        }
        return nil
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

/// The four points of a string's cubic Bézier, in world space.
struct StringCurve: Equatable, Sendable {
    var a: CGPoint
    var c1: CGPoint
    var c2: CGPoint
    var b: CGPoint

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let w0 = u * u * u
        let w1 = 3 * u * u * t
        let w2 = 3 * u * t * t
        let w3 = t * t * t
        return CGPoint(
            x: w0 * a.x + w1 * c1.x + w2 * c2.x + w3 * b.x,
            y: w0 * a.y + w1 * c1.y + w2 * c2.y + w3 * b.y
        )
    }

    /// The same curve, drawn from the other end.
    var reversed: StringCurve {
        StringCurve(a: b, c1: c2, c2: c1, b: a)
    }

    var path: CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addCurve(to: b, control1: c1, control2: c2)
        return path
    }

    /// `segments` straight pieces that follow the curve.
    func flattened(segments: Int = 16) -> [CGPoint] {
        (0...segments).map { point(at: CGFloat($0) / CGFloat(segments)) }
    }

    /// A box that contains the curve: the box around its control points.
    var bounds: CGRect {
        let xs = [a.x, c1.x, c2.x, b.x]
        let ys = [a.y, c1.y, c2.y, b.y]
        let minX = xs.min()!, minY = ys.min()!
        return CGRect(x: minX, y: minY, width: xs.max()! - minX, height: ys.max()! - minY)
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
