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
/// Text cards show a bitmap of their text, rendered per zoom tier by the canvas. Image cards
/// show a photo in a polaroid, photo or borderless frame, with an optional caption (also a
/// text bitmap). Web cards still show placeholder bars until M4.
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

    /// The whole image, faded, shown around the card while it's being reframed.
    private let ghost = CALayer()
    private let shadowLayers = CardNode.shadows.map { _ in CALayer() }
    private let body = CAGradientLayer()
    private let tintBand = CAGradientLayer()
    private let skeleton = CALayer()
    private let photo = CALayer()
    private let scrim = CAGradientLayer()
    /// Text of a text card, or the caption of an image card.
    private let content = CALayer()
    private let stroke = CAGradientLayer()
    private let strokeMask = CAShapeLayer()
    private let pin = PinNode()

    /// Zoom tier of the current text bitmap, or `nil` when there is none or it is stale.
    private(set) var renderedTier: CGFloat?
    private var detail = DetailLevel.full
    private var isLifted = false
    private var isEditing = false

    /// The decoded image (uncropped), how big a decode was asked for, and the crop shown
    /// while reframing.
    private(set) var fullImage: CGImage?
    var requestedLongSide: Int?
    private var framingCrop: CGRect?

    init(card: Card, appearance: CanvasAppearance, scale: CGFloat) {
        id = card.id
        self.card = card
        ghost.opacity = 0.35
        ghost.isHidden = true
        root.addSublayer(ghost)
        for layer in shadowLayers {
            layer.shadowColor = RGBA.black.cgColor
            root.addSublayer(layer)
        }
        body.cornerCurve = .continuous
        body.masksToBounds = true
        body.startPoint = CGPoint(x: 0.5, y: 0)
        body.endPoint = CGPoint(x: 0.5, y: 1)
        root.addSublayer(body)
        body.addSublayer(tintBand)
        body.addSublayer(skeleton)

        photo.masksToBounds = true
        photo.cornerCurve = .continuous
        root.addSublayer(photo)
        scrim.startPoint = CGPoint(x: 0.5, y: 0)
        scrim.endPoint = CGPoint(x: 0.5, y: 1)
        scrim.colors = [RGBA.black.opacity(0).cgColor, RGBA.black.opacity(0.55).cgColor]
        photo.addSublayer(scrim)
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

    var imagePayload: ImagePayload? {
        if case .image(let image) = card.content { return image }
        return nil
    }

    /// Whether the card shows text drawn by the text renderer: a text card, or a captioned photo.
    var hasTextContent: Bool {
        switch card.content {
        case .text: true
        case .image(let image): !(image.caption ?? "").isEmpty
        case .web: false
        }
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
        let radius = CanvasGeometry.cornerRadius(of: newCard)
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
        body.cornerRadius = radius
        body.colors = bodyFill(for: newCard, appearance: appearance).cgColors
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
            cornerWidth: max(radius - 0.5, 0), cornerHeight: max(radius - 0.5, 0), transform: nil
        )

        if let image = imagePayload {
            if image.asset != (old.content.imagePayload?.asset) {
                fullImage = nil
                requestedLongSide = nil
            } else if sizeChanged || image.crop != old.content.imagePayload?.crop {
                // A larger photo area or a tighter crop may need a bigger decode.
                requestedLongSide = nil
            }
            let photoRect = ImageCardLayout.photoRect(for: image.frameStyle, in: bounds.size)
            photo.frame = photoRect
            photo.cornerRadius = ImageCardLayout.photoCornerRadius(for: image.frameStyle)
            photo.backgroundColor = appearance.skeleton.opacity(min(appearance.skeleton.alpha * 3, 1)).cgColor
            scrim.frame = CGRect(x: 0, y: photoRect.height * 0.55, width: photoRect.width, height: photoRect.height * 0.45)
            content.frame = ImageCardLayout.captionRect(for: image.frameStyle, in: bounds.size)
            applyImage()
        } else {
            content.frame = bounds
        }

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

    private func bodyFill(for card: Card, appearance: CanvasAppearance) -> GradientPair {
        switch card.content {
        case .text(let text): text.style == .typewriter ? appearance.paperFill : appearance.cardFill
        case .image(let image): image.frameStyle == .borderless ? appearance.cardFill : appearance.photoPaper
        case .web: appearance.cardFill
        }
    }

    // MARK: Photo

    /// Shows a decode of the card's image. The node keeps the whole image and crops it itself,
    /// so reframing and resizing never need a new decode unless more pixels are required.
    func setImage(_ image: CGImage) {
        fullImage = image
        applyImage()
        applyVisibility()
    }

    func discardImage() {
        guard fullImage != nil || requestedLongSide != nil else { return }
        fullImage = nil
        requestedLongSide = nil
        photo.contents = nil
        applyVisibility()
    }

    /// The image's aspect ratio, once known.
    var imageAspect: CGFloat? {
        fullImage.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) }
    }

    /// While reframing, shows `crop` (normalized, already matching the photo's aspect ratio)
    /// and the whole image faded around the card. `nil` ends reframing.
    func setFraming(_ crop: CGRect?) {
        framingCrop = crop
        // Above every other card, so the faded rest of the image isn't hidden under them.
        root.zPosition = crop == nil && !isLifted ? CGFloat(card.z) : 1_000_000
        applyImage()
    }

    /// The normalized part of the image the photo area shows right now.
    var visibleCrop: CGRect? {
        guard let image = imagePayload, let aspect = imageAspect else { return nil }
        return framingCrop ?? ImageCardLayout.visibleCrop(crop: image.crop, imageAspect: aspect, photoSize: photo.bounds.size)
    }

    var photoFrame: CGRect { photo.frame }

    private func applyImage() {
        guard let full = fullImage, let crop = visibleCrop else {
            photo.contents = nil
            ghost.isHidden = true
            return
        }
        let imageSize = CGSize(width: full.width, height: full.height)
        photo.contents = full.cropping(to: ImageCardLayout.pixelRect(for: crop, imageSize: imageSize)) ?? full
        if let framing = framingCrop {
            let photoRect = photo.frame
            let size = CGSize(width: photoRect.width / framing.width, height: photoRect.height / framing.height)
            ghost.contents = full
            ghost.frame = CGRect(
                x: photoRect.minX - framing.minX * size.width,
                y: photoRect.minY - framing.minY * size.height,
                width: size.width, height: size.height
            )
            ghost.isHidden = false
        } else {
            ghost.contents = nil
            ghost.isHidden = true
        }
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
        let image = imagePayload
        stroke.isHidden = detail != .full || (image != nil && image?.frameStyle != .borderless)
        body.borderWidth = detail == .full || image != nil ? 0 : 1
        pin.root.isHidden = !showsDetail
        photo.isHidden = image == nil
        let captioned = !(image?.caption ?? "").isEmpty
        scrim.isHidden = !showsDetail || !captioned || !ImageCardLayout.captionIsOverlaid(for: image?.frameStyle ?? .polaroid)
        content.isHidden = !showsDetail || isEditing || !hasTextContent
        // Text cards show placeholder bars only until their first bitmap arrives.
        skeleton.isHidden = !showsDetail || isEditing || image != nil || (isTextCard && content.contents != nil)
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

        case .image:
            return []

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

extension CardContent {
    var imagePayload: ImagePayload? {
        if case .image(let image) = self { return image }
        return nil
    }
}
