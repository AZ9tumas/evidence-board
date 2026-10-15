import Foundation
import QuartzCore
import BoardKit

/// Selection rings in world space, around each selected card.
///
/// A single selection gets a slowly turning gradient ring. Several selected cards get plain
/// rings, which stay cheap even with hundreds selected. Ring widths are recomputed when the
/// zoom settles, so they stay about 2 pt on screen.
@MainActor
final class SelectionRings {
    static let outset: CGFloat = 4
    static let lineWidth: CGFloat = 2

    let layer = CALayer()
    private var rings: [UUID: CALayer] = [:]
    private var zoom: CGFloat = 1
    private var appearance: CanvasAppearance
    private let reduceMotion: Bool

    init(appearance: CanvasAppearance, reduceMotion: Bool) {
        self.appearance = appearance
        self.reduceMotion = reduceMotion
    }

    /// Rebuilds the rings for `cards`.
    func show(_ cards: [Card], zoom: CGFloat, appearance: CanvasAppearance) {
        self.zoom = zoom
        self.appearance = appearance
        layer.sublayers = nil
        rings = [:]
        let animated = cards.count == 1
        for card in cards {
            let ring = animated ? makeGradientRing() : makePlainRing()
            rings[card.id] = ring
            layer.addSublayer(ring)
            place(ring, around: card, frame: card.frame)
        }
    }

    /// Follows a card that moved or resized, without rebuilding the ring.
    func move(_ card: Card, to frame: Rect) {
        guard let ring = rings[card.id] else { return }
        place(ring, around: card, frame: frame)
    }

    /// Keeps rings about 2 pt wide on screen after the zoom changes.
    func setZoom(_ zoom: CGFloat, cards: [Card]) {
        guard zoom != self.zoom else { return }
        self.zoom = zoom
        for card in cards { move(card, to: card.frame) }
    }

    private func place(_ ring: CALayer, around card: Card, frame: Rect) {
        let outset = Self.outset / zoom
        let size = CGSize(width: CGFloat(frame.width) + outset * 2, height: CGFloat(frame.height) + outset * 2)
        let bounds = CGRect(origin: .zero, size: size)
        let radius = CanvasGeometry.cornerRadius(of: card) + outset
        let path = CGPath(roundedRect: bounds.insetBy(dx: 0.5 / zoom, dy: 0.5 / zoom), cornerWidth: radius, cornerHeight: radius, transform: nil)

        ring.bounds = bounds
        ring.position = CGPoint(x: CGFloat(frame.midX), y: CGFloat(frame.midY))
        ring.zPosition = 2_000_000
        ring.setAffineTransform(CGAffineTransform(rotationAngle: CanvasGeometry.radians(card.rotation)))
        if let shape = ring as? CAShapeLayer {
            shape.path = path
            shape.lineWidth = Self.lineWidth / zoom
        } else if let mask = ring.mask as? CAShapeLayer, let gradient = ring.sublayers?.first {
            mask.frame = bounds
            mask.path = path
            mask.lineWidth = Self.lineWidth / zoom
            let side = hypot(size.width, size.height)
            gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            gradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    private func makePlainRing() -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.fillColor = nil
        ring.strokeColor = appearance.selection.from.cgColor
        return ring
    }

    private func makeGradientRing() -> CALayer {
        let ring = CALayer()
        let gradient = CAGradientLayer()
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.colors = [appearance.selection.from, appearance.selection.to, appearance.selection.from].map(\.cgColor)
        if !reduceMotion {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 12
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            gradient.add(spin, forKey: "spin")
        }
        ring.addSublayer(gradient)

        let mask = CAShapeLayer()
        mask.fillColor = nil
        mask.strokeColor = RGBA.black.cgColor
        ring.mask = mask
        return ring
    }
}

/// Resize handles and the marquee, drawn in view space so they keep a constant size.
@MainActor
final class HandleOverlay {
    static let handleSize: CGFloat = 10
    static let hitRadius: CGFloat = 9

    let layer = CALayer()
    private var handles: [ResizeHandle: CALayer] = [:]
    private let marquee = CAShapeLayer()
    private(set) var handlePoints: [ResizeHandle: CGPoint] = [:]

    init() {
        for handle in ResizeHandle.allCases {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: Self.handleSize, height: Self.handleSize)
            dot.cornerRadius = Self.handleSize / 2
            dot.backgroundColor = RGBA.white.cgColor
            dot.borderWidth = 1.5
            dot.shadowColor = RGBA.black.cgColor
            dot.shadowOpacity = 0.4
            dot.shadowRadius = 2
            dot.shadowOffset = CGSize(width: 0, height: 1)
            dot.shadowPath = CGPath(ellipseIn: dot.bounds, transform: nil)
            dot.isHidden = true
            handles[handle] = dot
            layer.addSublayer(dot)
        }
        marquee.lineWidth = 1
        marquee.isHidden = true
        layer.addSublayer(marquee)
    }

    func setAppearance(_ appearance: CanvasAppearance) {
        for dot in handles.values { dot.borderColor = appearance.selection.from.cgColor }
        marquee.strokeColor = appearance.selection.from.opacity(0.9).cgColor
        marquee.fillColor = appearance.selection.from.opacity(0.12).cgColor
    }

    /// Puts handles on the corners of `frame` (a card rect in world space), or hides them.
    func showHandles(for card: Card?, frame: Rect?, camera: Camera, viewSize: CGSize) {
        guard let card, let frame else {
            for dot in handles.values { dot.isHidden = true }
            handlePoints = [:]
            return
        }
        var moved = card
        moved.frame = frame
        let outset = SelectionRings.outset / camera.zoom
        for handle in ResizeHandle.allCases {
            let (sx, sy) = handle.signs
            let local = CGPoint(x: sx * (CGFloat(frame.width) / 2 + outset), y: sy * (CGFloat(frame.height) / 2 + outset))
            let point = camera.worldToView(CanvasGeometry.worldPoint(local, in: moved), in: viewSize)
            handlePoints[handle] = point
            handles[handle]?.position = point
            handles[handle]?.isHidden = false
        }
    }

    /// The handle under `point` (view space), if any.
    func handle(at point: CGPoint) -> ResizeHandle? {
        handlePoints.first { hypot($0.value.x - point.x, $0.value.y - point.y) <= Self.hitRadius }?.key
    }

    func showMarquee(_ rect: CGRect?) {
        guard let rect else {
            marquee.isHidden = true
            return
        }
        marquee.isHidden = false
        marquee.path = CGPath(rect: rect.insetBy(dx: 0.5, dy: 0.5), transform: nil)
    }
}
