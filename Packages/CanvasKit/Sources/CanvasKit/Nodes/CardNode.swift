import Foundation
import QuartzCore
import BoardKit

/// How much of a card to draw, chosen from the zoom level (DESIGN.md §10.4).
enum DetailLevel: Comparable, Sendable {
    /// Below 15%: flat body only.
    case minimal
    /// 15–40%: one shadow, plain border, low-resolution text.
    case reduced
    /// 40% and up: everything.
    case full

    init(zoom: CGFloat) {
        self = zoom < 0.15 ? .minimal : zoom < 0.4 ? .reduced : .full
    }
}

/// The layers for one card: layered shadows, gradient body and stroke, content and pin.
///
/// Text cards show a bitmap of their text, rendered per zoom tier by the canvas. Image and
/// web cards still show placeholder bars until M2 and M4.
@MainActor
final class CardNode {
    private struct Shadow {
        let offset: CGFloat
        let blur: CGFloat
        let opacity: Float
    }

    /// Contact, mid and ambient shadows. Together they make a card look pinned on, not flat.
    private static let shadows = [
        Shadow(offset: 1, blur: 2, opacity: 0.35),
        Shadow(offset: 6, blur: 14, opacity: 0.28),
        Shadow(offset: 18, blur: 40, opacity: 0.22),
    ]

    let id: UUID
    private(set) var card: Card
    /// Positioned and rotated in world space.
    let root = CALayer()

    private let shadowLayers = CardNode.shadows.map { _ in CALayer() }
    private let body = CAGradientLayer()
    private let tintBand = CAGradientLayer()
    private let skeleton = CALayer()
    private let content = CALayer()
    private let stroke = CAGradientLayer()
    private let strokeMask = CAShapeLayer()
    private let pin = PinNode()

    /// Zoom tier of the current text bitmap, or `nil` when there is none or it is stale.
    private(set) var renderedTier: CGFloat?
    private var detail = DetailLevel.full
    private var isLifted = false
    private var isEditing = false

    init(card: Card, appearance: CanvasAppearance, scale: CGFloat) {
        id = card.id
        self.card = card
        for layer in shadowLayers {
            layer.shadowColor = RGBA.black.cgColor
            root.addSublayer(layer)
        }
        body.cornerRadius = CanvasGeometry.cardCornerRadius
        body.cornerCurve = .continuous
        body.masksToBounds = true
        body.startPoint = CGPoint(x: 0.5, y: 0)
        body.endPoint = CGPoint(x: 0.5, y: 1)
        root.addSublayer(body)
        body.addSublayer(tintBand)
        body.addSublayer(skeleton)
        root.addSublayer(content)

        strokeMask.fillColor = nil
        strokeMask.strokeColor = RGBA.black.cgColor
        strokeMask.lineWidth = 1
        stroke.mask = strokeMask
        stroke.startPoint = CGPoint(x: 0.5, y: 0)
        stroke.endPoint = CGPoint(x: 0.5, y: 1)
        root.addSublayer(stroke)
        root.addSublayer(pin.root)

        update(card: card, appearance: appearance)
        setContentsScale(scale)
    }

    var isTextCard: Bool {
        if case .text = card.content { return true }
        return false
    }

    func setContentsScale(_ scale: CGFloat) {
        var stack: [CALayer] = [root]
        while let layer = stack.popLast() {
            if layer !== content { layer.contentsScale = scale }
            stack.append(contentsOf: layer.sublayers ?? [])
            if let mask = layer.mask { stack.append(mask) }
        }
    }

    // MARK: Updating

    /// Applies a new version of the card. Returns whether the text bitmap must be redrawn.
    @discardableResult
    func update(card newCard: Card, appearance: CanvasAppearance) -> Bool {
        let old = card
        card = newCard
        let sizeChanged = old.frame.width != newCard.frame.width || old.frame.height != newCard.frame.height
        let contentChanged = old.content != newCard.content
        let needsRender = sizeChanged || contentChanged || renderedTier == nil

        let bounds = CGRect(x: 0, y: 0, width: newCard.frame.width, height: newCard.frame.height)
        let radius = CanvasGeometry.cardCornerRadius
        let outline = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

        root.bounds = bounds
        root.position = CGPoint(x: newCard.frame.midX, y: newCard.frame.midY)
        root.zPosition = CGFloat(newCard.z)
        applyTransform()

        // Explicit shadow paths keep Core Animation from rendering shadows off screen every frame.
        for layer in shadowLayers {
            layer.frame = bounds
            layer.shadowPath = outline
        }
        applyShadows()

        body.frame = bounds
        let isPaper: Bool
        if case .text(let text) = newCard.content, text.style == .typewriter { isPaper = true } else { isPaper = false }
        body.colors = (isPaper ? appearance.paperFill : appearance.cardFill).cgColors
        body.borderColor = appearance.cardStroke.from.cgColor

        if let tint = newCard.tint {
            let color = appearance.gradient(for: tint).from
            tintBand.isHidden = false
            tintBand.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(64, bounds.height))
            tintBand.colors = [color.opacity(0.30).cgColor, color.opacity(0).cgColor]
        } else {
            tintBand.isHidden = true
        }

        stroke.frame = bounds
        stroke.colors = appearance.cardStroke.cgColors
        strokeMask.frame = bounds
        strokeMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: radius - 0.5, cornerHeight: radius - 0.5, transform: nil
        )

        content.frame = bounds
        if needsRender && sizeChanged {
            // A resized bitmap would look stretched; better blank for a frame than distorted.
            content.contents = nil
            renderedTier = nil
        } else if contentChanged {
            renderedTier = nil
        }

        skeleton.frame = bounds
        if sizeChanged || contentChanged || skeleton.sublayers == nil {
            skeleton.sublayers = Self.placeholders(for: newCard, in: bounds.size, appearance: appearance)
        }

        pin.root.position = CGPoint(x: bounds.midX, y: CanvasGeometry.pinInset)
        pin.update(locked: newCard.locked, appearance: appearance)
        applyVisibility()
        return needsRender
    }

    /// Moves the card without touching anything else, for live dragging.
    func setPosition(_ frame: Rect) {
        root.position = CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: Text bitmap

    func setRenderedText(_ image: CGImage?, tier: CGFloat, scale: CGFloat) {
        content.contents = image
        content.contentsScale = scale
        renderedTier = image == nil ? nil : tier
        applyVisibility()
    }

    /// Frees the bitmap of a card that scrolled far out of view.
    func discardRenderedText() {
        guard renderedTier != nil || content.contents != nil else { return }
        content.contents = nil
        renderedTier = nil
        applyVisibility()
    }

    var hasRenderedText: Bool { content.contents != nil }

    // MARK: States

    func setDetail(_ level: DetailLevel) {
        guard level != detail else { return }
        detail = level
        applyShadows()
        applyVisibility()
    }

    /// Picked up for dragging: slightly larger, with deeper shadows, and above everything.
    func setLifted(_ lifted: Bool) {
        guard lifted != isLifted else { return }
        isLifted = lifted
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        root.zPosition = lifted ? 1_000_000 : CGFloat(card.z)
        applyTransform()
        applyShadows()
        CATransaction.commit()
    }

    /// While the live editor is open, its own text replaces the bitmap.
    func setEditing(_ editing: Bool) {
        isEditing = editing
        applyVisibility()
    }

    private func applyTransform() {
        var transform = CATransform3DMakeRotation(CanvasGeometry.radians(card.rotation), 0, 0, 1)
        if isLifted { transform = CATransform3DScale(transform, 1.02, 1.02, 1) }
        root.transform = transform
    }

    private func applyShadows() {
        let lift: (offset: CGFloat, blur: CGFloat) = isLifted ? (1.8, 1.6) : (1, 1)
        for (index, (layer, shadow)) in zip(shadowLayers, Self.shadows).enumerated() {
            let visible = switch detail {
            case .full: true
            case .reduced: index == 1
            case .minimal: false
            }
            layer.isHidden = !visible
            layer.shadowOffset = CGSize(width: 0, height: shadow.offset * lift.offset)
            layer.shadowRadius = shadow.blur * lift.blur / 2
            layer.shadowOpacity = shadow.opacity
        }
    }

    private func applyVisibility() {
        let showsDetail = detail != .minimal
        stroke.isHidden = detail != .full
        body.borderWidth = detail == .full ? 0 : 1
        pin.root.isHidden = !showsDetail
        content.isHidden = !showsDetail || isEditing || !isTextCard
        // Text cards show placeholder bars only until their first bitmap arrives.
        skeleton.isHidden = !showsDetail || isEditing || (isTextCard && content.contents != nil)
    }

    // MARK: Placeholders

    private static func placeholders(for card: Card, in size: CGSize, appearance: CanvasAppearance) -> [CALayer] {
        let bar = appearance.skeleton
        switch card.content {
        case .text(let text):
            let height: CGFloat = switch text.style {
            case .headline: 16
            case .note: 8
            case .typewriter: 7
            }
            return lines(from: TextCardTypography.insets.top + 4, height: height, in: size, color: bar)

        case .image(let image):
            let well: CGRect = switch image.frameStyle {
            case .polaroid: CGRect(x: 12, y: 12, width: size.width - 24, height: max(size.height - 56, 0))
            case .borderless: CGRect(origin: .zero, size: size)
            case .photo: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16)
            }
            var layers = [block(well, colors: [bar.opacity(bar.alpha * 2.2), bar.opacity(bar.alpha * 1.2)], radius: 6)]
            if image.caption != nil, image.frameStyle == .polaroid {
                layers.append(block(
                    CGRect(x: 18, y: size.height - 28, width: size.width * 0.5, height: 8),
                    colors: [bar, bar], radius: 4
                ))
            }
            return layers

        case .web(let web):
            let heroHeight = min(size.width * 9 / 16, size.height * 0.55)
            let hero = CGRect(x: 0, y: 0, width: size.width, height: heroHeight)
            let heroColors: [RGBA]
            if let palette = web.snapshot?.palette,
               let top = RGBA(hex: palette.darkVibrant), let bottom = RGBA(hex: palette.darkMuted) {
                heroColors = [top, bottom]
            } else {
                heroColors = [bar.opacity(bar.alpha * 2.2), bar.opacity(bar.alpha * 1.2)]
            }
            var layers = [block(hero, colors: heroColors, radius: 0)]
            layers.append(block(CGRect(x: 18, y: heroHeight + 16, width: size.width * 0.38, height: 6), colors: [bar, bar], radius: 3))
            layers += lines(from: heroHeight + 34, height: 10, in: size, color: bar)
            return layers
        }
    }

    /// Text-like bars of varying width that fill the card from `top` down.
    private static func lines(from top: CGFloat, height: CGFloat, in size: CGSize, color: RGBA) -> [CALayer] {
        let widths: [CGFloat] = [0.82, 0.94, 0.68, 0.88, 0.56, 0.9, 0.74]
        let spacing = max(height * 1.9, 14)
        var layers: [CALayer] = []
        var y = top
        var index = 0
        while y + height <= size.height - 18 {
            let width = (size.width - 36) * widths[index % widths.count]
            layers.append(block(CGRect(x: 18, y: y, width: width, height: height), colors: [color, color], radius: height / 2))
            y += spacing
            index += 1
        }
        return layers
    }

    private static func block(_ frame: CGRect, colors: [RGBA], radius: CGFloat) -> CALayer {
        let layer = CAGradientLayer()
        layer.frame = frame
        layer.colors = colors.map(\.cgColor)
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = radius > 0
        return layer
    }
}

/// The glossy push-pin at the top of a card. Strings attach to its center.
@MainActor
final class PinNode {
    let root = CALayer()
    private let head = CAGradientLayer()
    private let glint = CALayer()

    init() {
        let diameter = CanvasGeometry.pinDiameter
        let bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        root.bounds = bounds
        root.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        root.shadowColor = RGBA.black.cgColor
        root.shadowOpacity = 0.5
        root.shadowRadius = 1.5
        root.shadowOffset = CGSize(width: 1.5, height: 2.5)

        head.frame = bounds
        head.type = .radial
        head.startPoint = CGPoint(x: 0.35, y: 0.3)
        head.endPoint = CGPoint(x: 1.05, y: 1.0)
        head.cornerRadius = diameter / 2
        head.masksToBounds = true
        root.addSublayer(head)

        glint.frame = CGRect(x: 3.5, y: 3, width: 4, height: 3.5)
        glint.cornerRadius = 1.75
        glint.backgroundColor = RGBA.white.opacity(0.7).cgColor
        root.addSublayer(glint)
    }

    func update(locked: Bool, appearance: CanvasAppearance) {
        head.colors = (locked ? appearance.lockedPin : appearance.pin).cgColors
    }
}
