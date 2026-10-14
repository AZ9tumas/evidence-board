import Foundation
import QuartzCore
import BoardKit

/// The layers for one card.
///
/// In M0 a card is drawn as a styled skeleton: the real card body with its layered shadows,
/// gradient fill and stroke, plus placeholder bars shaped like its content. Rendered text,
/// images and link previews replace the bars in M1–M4.
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
    /// Positioned and rotated in world space. Holds everything except the pin.
    let root = CALayer()
    let pin = PinNode()

    private let shadowLayers = CardNode.shadows.map { _ in CALayer() }
    private let body = CAGradientLayer()
    private let tintBand = CAGradientLayer()
    private let skeleton = CALayer()
    private let stroke = CAGradientLayer()
    private let strokeMask = CAShapeLayer()

    init(card: Card, appearance: CanvasAppearance, scale: CGFloat) {
        id = card.id
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

        strokeMask.fillColor = nil
        strokeMask.strokeColor = RGBA.black.cgColor
        strokeMask.lineWidth = 1
        stroke.mask = strokeMask
        stroke.startPoint = CGPoint(x: 0.5, y: 0)
        stroke.endPoint = CGPoint(x: 0.5, y: 1)
        root.addSublayer(stroke)

        update(card: card, appearance: appearance)
        setContentsScale(scale)
    }

    func setContentsScale(_ scale: CGFloat) {
        var stack: [CALayer] = [root, pin.root]
        while let layer = stack.popLast() {
            layer.contentsScale = scale
            stack.append(contentsOf: layer.sublayers ?? [])
            if let mask = layer.mask { stack.append(mask) }
        }
    }

    func update(card: Card, appearance: CanvasAppearance) {
        let bounds = CGRect(x: 0, y: 0, width: card.frame.width, height: card.frame.height)
        let radius = CanvasGeometry.cardCornerRadius
        let outline = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

        root.bounds = bounds
        root.position = CGPoint(x: card.frame.midX, y: card.frame.midY)
        root.setAffineTransform(CGAffineTransform(rotationAngle: CanvasGeometry.radians(card.rotation)))

        // Explicit shadow paths keep Core Animation from rendering shadows off screen every frame.
        for (layer, shadow) in zip(shadowLayers, Self.shadows) {
            layer.frame = bounds
            layer.shadowPath = outline
            layer.shadowOffset = CGSize(width: 0, height: shadow.offset)
            layer.shadowRadius = shadow.blur / 2
            layer.shadowOpacity = shadow.opacity
        }

        body.frame = bounds
        body.colors = appearance.cardFill.cgColors

        if let tint = card.tint {
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

        skeleton.frame = bounds
        skeleton.sublayers = Self.placeholders(for: card, in: bounds.size, appearance: appearance)

        pin.update(position: CanvasGeometry.pinPoint(of: card), locked: card.locked, appearance: appearance)
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
            return lines(from: 34, height: height, in: size, color: bar)

        case .image(let image):
            let well: CGRect = switch image.frameStyle {
            case .polaroid: CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 56)
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

    func update(position: CGPoint, locked: Bool, appearance: CanvasAppearance) {
        root.position = position
        head.colors = (locked ? appearance.lockedPin : appearance.pin).cgColors
    }
}
