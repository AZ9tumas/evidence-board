import AppKit
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
/// text bitmap). Web cards add a mesh gradient, an ambient glow, the page image, favicon and
/// badges from `WebCardParts`, with all their text in one bitmap.
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
    /// A colored halo around search matches.
    private let glow = CALayer()
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
    /// Changes whenever the text bitmap is replaced, dropped or out of date, so a bitmap drawn
    /// in the background for an older version is thrown away. Unique across nodes, so a node
    /// rebuilt for a new theme never takes the old one's bitmap.
    private(set) var textVersion: Int
    private static var lastTextVersion = 0

    private static func newTextVersion() -> Int {
        lastTextVersion += 1
        return lastTextVersion
    }
    private var detail = DetailLevel.full
    private var isLifted = false
    private var isEditing = false
    /// Above the Focus/Trace dimming layer.
    private var isRaised = false
    /// The theme's shadow strength (the alpha of its shadow color).
    private var shadowStrength: Float = 1

    /// The decoded image (uncropped), how big a decode was asked for, and the crop shown
    /// while reframing.
    private(set) var fullImage: CGImage?
    var requestedLongSide: Int?
    private var framingCrop: CGRect?

    /// Web cards only.
    private var web: WebCardParts?
    private(set) var webContent: WebCardContent?
    private(set) var webLayout: WebCardLayout?

    init(card: Card, appearance: CanvasAppearance, scale: CGFloat) {
        id = card.id
        self.card = card
        textVersion = Self.newTextVersion()
        ghost.opacity = 0.35
        ghost.isHidden = true
        root.addSublayer(ghost)
        glow.isHidden = true
        glow.shadowOffset = .zero
        root.addSublayer(glow)
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

    /// Whether the card shows text drawn by the text renderer: a text card, a captioned
    /// photo, or a web card with its preview.
    var hasTextContent: Bool {
        switch card.content {
        case .text: true
        case .image(let image): !(image.caption ?? "").isEmpty
        case .web: !(webLayout?.blocks.isEmpty ?? true)
        }
    }

    var isWebCard: Bool {
        if case .web = card.content { return true }
        return false
    }

    var requestedIconSide: Int? {
        get { web?.requestedIconSide }
        set { web?.requestedIconSide = newValue }
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

    /// Applies a new version of the card. Web cards also take what their preview shows;
    /// without it they keep the last one. Returns whether the text bitmap must be redrawn.
    @discardableResult
    func update(card newCard: Card, appearance: CanvasAppearance, web newWeb: WebCardContent? = nil) -> Bool {
        let old = card
        card = newCard
        let sizeChanged = old.frame.width != newCard.frame.width || old.frame.height != newCard.frame.height
        let webChanged = newWeb != nil && newWeb != webContent
        let contentChanged = old.content != newCard.content || webChanged
        let needsRender = sizeChanged || contentChanged || renderedTier == nil

        let bounds = CGRect(x: 0, y: 0, width: newCard.frame.width, height: newCard.frame.height)
        let radius = CanvasGeometry.cornerRadius(of: newCard)
        let outline = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

        root.bounds = bounds
        root.position = CGPoint(x: newCard.frame.midX, y: newCard.frame.midY)
        applyZ()
        applyTransform()

        // Explicit shadow paths keep Core Animation from rendering shadows off screen every frame.
        let shadowColor = appearance.shadow.opacity(1).cgColor
        for layer in shadowLayers {
            layer.frame = bounds
            layer.shadowPath = outline
            layer.shadowColor = shadowColor
        }
        shadowStrength = Float(appearance.shadow.alpha)
        applyShadows()
        glow.frame = bounds
        glow.shadowPath = outline

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

        if isWebCard, let content = newWeb ?? webContent {
            applyWeb(content, bounds: bounds, appearance: appearance, contentChanged: contentChanged || sizeChanged)
        } else if let image = imagePayload {
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
            textVersion = Self.newTextVersion()
        } else if contentChanged {
            renderedTier = nil
            textVersion = Self.newTextVersion()
        }

        skeleton.frame = bounds
        if let web, let layout = webLayout {
            if sizeChanged || contentChanged || skeleton.sublayers == nil {
                skeleton.sublayers = layout.skeletonBars.isEmpty ? [] : web.skeletonLayers(for: layout, bounds: bounds, appearance: appearance)
            }
        } else if sizeChanged || contentChanged || skeleton.sublayers == nil {
            skeleton.sublayers = Self.placeholders(for: newCard, in: bounds.size, appearance: appearance)
        }

        pin.root.position = CGPoint(x: bounds.midX, y: CanvasGeometry.pinInset)
        pin.update(locked: newCard.locked, appearance: appearance)
        applyVisibility()
        return needsRender
    }

    // MARK: Web

    private func applyWeb(_ content: WebCardContent, bounds: CGRect, appearance: CanvasAppearance, contentChanged: Bool) {
        let parts = web ?? makeWebParts()
        if contentChanged || webLayout == nil || webContent != content {
            if webContent?.palette != content.palette || webContent?.imageAspect != content.imageAspect {
                // A new preview: the old decodes don't apply any more.
                fullImage = nil
                requestedLongSide = nil
                parts.discardImages()
            }
            webContent = content
            webLayout = WebCardLayout(content: content, width: bounds.width, appearance: appearance)
        }
        guard let layout = webLayout else { return }
        parts.apply(layout, content: content, bounds: bounds, appearance: appearance)
        stroke.colors = [
            (RGBA(hex: content.palette.vibrant) ?? appearance.cardStroke.from).opacity(0.6).cgColor,
            (RGBA(hex: content.palette.vibrant) ?? appearance.cardStroke.from).opacity(0).cgColor,
        ]
        let imageRect = layout.image ?? .zero
        photo.frame = imageRect
        photo.cornerRadius = WebCardLayout.heroCornerRadius
        photo.backgroundColor = (RGBA(hex: content.palette.darkMuted) ?? appearance.skeleton).cgColor
        let darkMuted = RGBA(hex: content.palette.darkMuted) ?? .black
        scrim.colors = [darkMuted.opacity(0).cgColor, darkMuted.opacity(0.85).cgColor]
        scrim.frame = layout.wash.map { $0.offsetBy(dx: -imageRect.minX, dy: -imageRect.minY) } ?? .zero
        self.content.frame = bounds
        if layout.icon != nil, parts.iconImage == nil, !content.imageIsAvatar {
            parts.setMonogram(for: content, side: layout.icon!.width, scale: max(root.contentsScale, 2))
        }
        applyImage()
    }

    private func makeWebParts() -> WebCardParts {
        let parts = WebCardParts()
        root.insertSublayer(parts.glow, at: 0)
        body.insertSublayer(parts.mesh, at: 0)
        // Badges and the favicon sit above the photo, below the text.
        root.insertSublayer(parts.icon, below: content)
        root.insertSublayer(parts.play, below: content)
        root.insertSublayer(parts.badge, below: content)
        web = parts
        return parts
    }

    /// Shows a decode of the site icon.
    func setIcon(_ image: CGImage) {
        web?.setIcon(image, usesHeroAsAvatar: webContent?.imageIsAvatar ?? false)
        applyVisibility()
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
        let firstShown = photo.contents == nil
        fullImage = image
        web?.setHero(image, usesAsAvatar: webContent?.imageIsAvatar ?? false)
        applyImage()
        applyVisibility()
        // A photo fades in when it first arrives, not when a sharper decode replaces it.
        if firstShown, photo.contents != nil {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = Motion.isReduced ? 0.15 : 0.3
            photo.add(fade, forKey: "arrive")
        }
    }

    func discardImage() {
        guard fullImage != nil || requestedLongSide != nil || web?.requestedIconSide != nil else { return }
        fullImage = nil
        requestedLongSide = nil
        photo.contents = nil
        web?.discardImages()
        if let content = webContent, let side = webLayout?.icon?.width, !content.imageIsAvatar {
            web?.setMonogram(for: content, side: side, scale: max(root.contentsScale, 2))
        }
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
        applyZ()
        applyImage()
    }

    /// The normalized part of the image the photo area shows right now.
    var visibleCrop: CGRect? {
        guard let aspect = imageAspect else { return nil }
        if let image = imagePayload {
            return framingCrop ?? ImageCardLayout.visibleCrop(crop: image.crop, imageAspect: aspect, photoSize: photo.bounds.size)
        }
        // Web images fill their area, centered.
        guard isWebCard, photo.bounds.width > 0, photo.bounds.height > 0 else { return nil }
        return ImageCardLayout.visibleCrop(crop: nil, imageAspect: aspect, photoSize: photo.bounds.size)
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
        textVersion = Self.newTextVersion()
        content.contents = image
        content.contentsScale = scale
        renderedTier = image == nil ? nil : tier
        applyVisibility()
    }

    /// Frees the bitmap of a card that scrolled far out of view.
    func discardRenderedText() {
        textVersion = Self.newTextVersion()
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
    /// Put down, it settles back with a little spring (DESIGN.md §6.6).
    func setLifted(_ lifted: Bool) {
        guard lifted != isLifted else { return }
        isLifted = lifted
        CATransaction.begin()
        CATransaction.setAnimationDuration(lifted ? 0.14 : 0.3)
        applyZ()
        applyTransform()
        applyShadows()
        if !lifted, !Motion.isReduced {
            let settle = CASpringAnimation.spring(keyPath: "transform.scale", response: 0.3, damping: 0.7)
            settle.fromValue = 1.02
            settle.toValue = 1
            root.add(settle, forKey: "settle")
        }
        CATransaction.commit()
    }

    /// A new card arrives: it grows from 92%, fades in and drops the last 8 pt into place,
    /// on a spring. With Reduce Motion it only fades.
    func playEntrance() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = Motion.isReduced ? 0.15 : 0.2
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        root.add(fade, forKey: "entrance.fade")
        guard !Motion.isReduced else { return }
        let grow = CASpringAnimation.spring(keyPath: "transform.scale", response: 0.35, damping: 0.78)
        grow.fromValue = 0.92
        grow.toValue = 1
        root.add(grow, forKey: "entrance.grow")
        let drop = CASpringAnimation.spring(keyPath: "position.y", response: 0.35, damping: 0.78)
        drop.fromValue = -8
        drop.toValue = 0
        drop.isAdditive = true
        root.add(drop, forKey: "entrance.drop")
    }

    /// The preview arrived: the skeleton cross-fades into the finished card.
    func crossFadeContent() {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = Motion.isReduced ? 0.15 : 0.25
        root.add(fade, forKey: "resolve")
    }

    /// While the live editor is open, its own text replaces the bitmap.
    func setEditing(_ editing: Bool) {
        isEditing = editing
        applyVisibility()
    }

    /// Keeps the card above the dimming layer while Focus or Trace highlights it.
    func setRaised(_ raised: Bool) {
        guard raised != isRaised else { return }
        isRaised = raised
        applyZ()
    }

    /// Surrounds the card with a halo of `color`, stronger for the match being shown.
    func setGlow(_ color: RGBA?, strong: Bool) {
        glow.isHidden = color == nil
        guard let color else { return }
        glow.shadowColor = color.cgColor
        glow.shadowRadius = strong ? 16 : 9
        glow.shadowOpacity = strong ? 1 : 0.7
    }

    func setPinState(_ state: PinState) {
        pin.setState(state)
    }

    /// Stacking: file order, then raised above the dimming layer, then lifted or being
    /// reframed above everything (so the faded rest of a reframed photo isn't hidden).
    static let dimmingZ: CGFloat = 1_500_000

    private func applyZ() {
        let z = CGFloat(card.z)
        root.zPosition = isLifted || framingCrop != nil ? 4_000_000 + z : isRaised ? 2_000_000 + z : z
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
            layer.shadowOpacity = shadow.opacity * shadowStrength
        }
    }

    private func applyVisibility() {
        let showsDetail = detail != .minimal
        let image = imagePayload
        stroke.isHidden = detail != .full || (image != nil && image?.frameStyle != .borderless)
        body.borderWidth = detail == .full || image != nil ? 0 : 1
        pin.root.isHidden = !showsDetail
        content.isHidden = !showsDetail || isEditing || !hasTextContent
        if let web, let layout = webLayout {
            photo.isHidden = layout.image == nil
            scrim.isHidden = !showsDetail || layout.wash == nil
            skeleton.isHidden = !showsDetail || layout.skeletonBars.isEmpty
            web.glow.isHidden = !showsDetail || layout.image == nil || fullImage == nil || webContent?.variant == .social
            web.icon.isHidden = !showsDetail || layout.icon == nil
            web.play.isHidden = !showsDetail || layout.playButton == nil
            web.badge.isHidden = !showsDetail || layout.durationBadge == nil
            return
        }
        photo.isHidden = image == nil
        let captioned = !(image?.caption ?? "").isEmpty
        scrim.isHidden = !showsDetail || !captioned || !ImageCardLayout.captionIsOverlaid(for: image?.frameStyle ?? .polaroid)
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

        case .web:
            return [] // web cards draw their own skeleton (WebCardParts)
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

/// What a pin is doing, for the connect gesture (DESIGN.md §5.5).
enum PinState: Sendable {
    case normal
    /// The pointer is over its card: brighter and 1.15× larger.
    case hover
    /// A string is being pulled out of it.
    case active
    /// A string being pulled will tie on here: it pulses.
    case target
}

/// The glossy push-pin at the top of a card. Strings attach to its center.
@MainActor
final class PinNode {
    let root = CALayer()
    private let halo = CAGradientLayer()
    private let head = CAGradientLayer()
    private let glint = CALayer()
    private var colors = GradientPair(.white, .white)
    private var state = PinState.normal

    init() {
        let diameter = CanvasGeometry.pinDiameter
        let bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        root.bounds = bounds

        // A soft glow in the pin's color, shown while connecting.
        let haloSize = diameter * 2.6
        halo.bounds = CGRect(x: 0, y: 0, width: haloSize, height: haloSize)
        halo.position = CGPoint(x: bounds.midX, y: bounds.midY)
        halo.type = .radial
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        halo.opacity = 0
        root.addSublayer(halo)

        let needle = CALayer()
        needle.bounds = bounds
        needle.position = CGPoint(x: bounds.midX, y: bounds.midY)
        needle.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        needle.shadowColor = RGBA.black.cgColor
        needle.shadowOpacity = 0.5
        needle.shadowRadius = 1.5
        needle.shadowOffset = CGSize(width: 1.5, height: 2.5)
        root.addSublayer(needle)

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
        colors = locked ? appearance.lockedPin : appearance.pin
        halo.colors = [colors.from.opacity(0.7).cgColor, colors.from.opacity(0).cgColor]
        applyHead()
    }

    func setState(_ newState: PinState) {
        guard newState != state else { return }
        state = newState
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.12)
        let scale: CGFloat = switch state {
        case .normal: 1
        case .hover: 1.15
        case .active: 1.2
        case .target: 1.3
        }
        root.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        halo.opacity = switch state {
        case .normal: 0
        case .hover: 0.45
        case .active, .target: 0.9
        }
        applyHead()
        CATransaction.commit()

        halo.removeAnimation(forKey: "pulse")
        if state == .target && !Motion.isReduced {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.7
            grow.toValue = 1.5
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0.15
            let pulse = CAAnimationGroup()
            pulse.animations = [grow, fade]
            pulse.duration = 0.8
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
            halo.add(pulse, forKey: "pulse")
        }
    }

    private func applyHead() {
        // Brighter while it's the thing you're about to grab.
        let lift = state == .normal ? 0 : 0.22
        head.colors = [colors.from.mixed(with: .white, lift).cgColor, colors.to.mixed(with: .white, lift * 0.5).cgColor]
    }
}

extension CardContent {
    var imagePayload: ImagePayload? {
        if case .image(let image) = self { return image }
        return nil
    }
}
