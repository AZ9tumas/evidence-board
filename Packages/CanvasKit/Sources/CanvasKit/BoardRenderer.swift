import AppKit
import BoardKit

/// Draws a whole board into a picture, without a window: for Finder thumbnails and Quick Look
/// previews (DESIGN.md §12.1), and anything else that needs a board as an image.
///
/// It draws what the canvas draws, simplified: the theme's background, every card with its
/// shadow, body, text, photo or link preview, the strings with their sag, and the pins on top.
/// Text that would come out smaller than a few pixels is shown as placeholder bars.
@MainActor
public enum BoardRenderer {
    /// The board fitted into `maxSize` points, at `scale` pixels per point.
    public static func image(of board: Board, appearance: CanvasAppearance, maxSize: CGSize, scale: CGFloat) -> CGImage? {
        let content = contentRect(of: board)
        let fit = min(maxSize.width / content.width, maxSize.height / content.height)
        let size = CGSize(width: max((content.width * fit).rounded(), 16), height: max((content.height * fit).rounded(), 16))
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard pixels.width * pixels.height <= 64_000_000, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }

        // Top-left origin, in points.
        context.translateBy(x: 0, y: pixels.height)
        context.scaleBy(x: scale, y: -scale)
        drawBackground(in: context, size: size, appearance: appearance)

        // World coordinates from here on.
        let zoom = size.width / content.width
        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -content.minX, y: -content.minY)
        let pixelsPerPoint = zoom * scale
        if let surface = ThemeArtwork.surfaceTile(appearance.texture, color: appearance.gridDot, scale: 2) {
            context.saveGState()
            context.clip(to: content)
            context.setAlpha(min(max(zoom / 0.3, 0.15), 1))
            context.draw(surface, in: CGRect(x: 0, y: 0, width: 256, height: 256), byTiling: true)
            context.restoreGState()
        }

        let cards = board.cards.sorted { $0.z < $1.z }
        for card in cards {
            draw(card, board: board, in: context, appearance: appearance, pixelsPerPoint: pixelsPerPoint)
        }
        drawStrings(board, in: context, appearance: appearance)
        for card in cards {
            drawPin(of: card, in: context, appearance: appearance)
        }
        return context.makeImage()
    }

    /// PNG bytes of ``image(of:appearance:maxSize:scale:)``.
    public static func pngData(of board: Board, appearance: CanvasAppearance, maxSize: CGSize, scale: CGFloat) -> Data? {
        guard let image = image(of: board, appearance: appearance, maxSize: maxSize, scale: scale) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The cards' bounds with some board around them; a 4:3 patch for an empty board.
    static func contentRect(of board: Board) -> CGRect {
        guard let bounds = CanvasGeometry.contentBounds(of: board.cards) else {
            return CGRect(x: -400, y: -300, width: 800, height: 600)
        }
        let margin = max(bounds.width, bounds.height) * 0.05 + 40
        return bounds.insetBy(dx: -margin, dy: -margin)
    }

    // MARK: Background

    private static func drawBackground(in context: CGContext, size: CGSize, appearance: CanvasAppearance) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        if let gradient = CGGradient(colorsSpace: space, colors: appearance.background.cgColors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        let edge = appearance.vignette
        if edge.alpha > 0, let vignette = CGGradient(
            colorsSpace: space, colors: [edge.opacity(0).cgColor, edge.cgColor] as CFArray, locations: [0.55, 1]
        ) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.drawRadialGradient(
                vignette, startCenter: center, startRadius: 0, endCenter: center,
                endRadius: hypot(size.width, size.height) / 2, options: [.drawsAfterEndLocation]
            )
        }
    }

    // MARK: Cards

    private static func draw(_ card: Card, board: Board, in context: CGContext, appearance: CanvasAppearance, pixelsPerPoint: CGFloat) {
        let size = CGSize(width: card.frame.width, height: card.frame.height)
        let bounds = CGRect(origin: .zero, size: size)
        let outline = ThemeArtwork.outline(bounds, card: card, appearance: appearance)

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: CGFloat(card.frame.midX), y: CGFloat(card.frame.midY))
        context.rotate(by: CanvasGeometry.radians(card.rotation))
        context.translateBy(x: -size.width / 2, y: -size.height / 2)

        // One soft shadow. Shadow offsets are in device pixels, with y up.
        let fill = bodyFill(of: card, appearance: appearance)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -6 * pixelsPerPoint * appearance.design.shadowOffset), blur: 16 * pixelsPerPoint * appearance.design.shadowBlur,
            color: appearance.shadow.opacity(0.4 * appearance.shadow.alpha).cgColor
        )
        context.addPath(outline)
        context.setFillColor(fill.to.opacity(1).cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(outline)
        context.clip()
        drawVertical(fill, in: bounds, context: context)
        if let tint = card.tint {
            let color = appearance.gradient(for: tint).from
            drawVertical(GradientPair(color.opacity(0.3), color.opacity(0)), in: CGRect(x: 0, y: 0, width: size.width, height: min(64, size.height)), context: context)
        }
        context.addPath(ThemeArtwork.ornament(in: bounds, style: appearance.design.ornament))
        context.setStrokeColor(appearance.text.opacity(appearance.design.ornament == .chalk ? 0.3 : 0.16).cgColor)
        context.setLineWidth(0.8)
        context.strokePath()
        switch card.content {
        case .text(let text):
            drawText(text, size: size, context: context, appearance: appearance, pixelsPerPoint: pixelsPerPoint)
        case .image(let photo):
            drawPhoto(photo, size: size, board: board, context: context, appearance: appearance, pixelsPerPoint: pixelsPerPoint)
        case .web(let web):
            drawLink(web, size: size, board: board, context: context, appearance: appearance, pixelsPerPoint: pixelsPerPoint)
        }
        context.restoreGState()

        context.addPath(ThemeArtwork.outline(bounds.insetBy(dx: appearance.design.borderWidth / 2, dy: appearance.design.borderWidth / 2), card: card, appearance: appearance))
        context.setStrokeColor(appearance.cardStroke.from.cgColor)
        context.setLineWidth(appearance.design.borderWidth)
        context.strokePath()
    }

    private static func bodyFill(of card: Card, appearance: CanvasAppearance) -> GradientPair {
        switch card.content {
        case .text(let text): text.style == .typewriter ? appearance.paperFill : appearance.cardFill
        case .image(let image): image.frameStyle == .borderless ? appearance.cardFill : appearance.photoPaper
        case .web: appearance.cardFill
        }
    }

    /// Text smaller than this many pixels per point is drawn as bars instead.
    private static let legibleScale: CGFloat = 0.2

    private static func drawText(_ text: TextPayload, size: CGSize, context: CGContext, appearance: CanvasAppearance, pixelsPerPoint: CGFloat) {
        guard pixelsPerPoint >= legibleScale else {
            drawBars(in: size, color: appearance.text.opacity(0.18), context: context)
            return
        }
        let image = TextCardTypography.render(text, size: size, scale: min(pixelsPerPoint, 4), appearance: appearance)
        draw(image, in: CGRect(origin: .zero, size: size), context: context)
    }

    private static func drawPhoto(
        _ photo: ImagePayload, size: CGSize, board: Board, context: CGContext, appearance: CanvasAppearance, pixelsPerPoint: CGFloat
    ) {
        let area = ImageCardLayout.photoRect(for: photo.frameStyle, in: size)
        drawPicture(
            asset: photo.asset, crop: photo.crop, in: area, cornerRadius: ImageCardLayout.photoCornerRadius(for: photo.frameStyle),
            board: board, context: context, placeholder: appearance.skeleton, pixelsPerPoint: pixelsPerPoint
        )
        drawPhotoMount(in: area, context: context, appearance: appearance)
        guard let caption = photo.caption, !caption.isEmpty, pixelsPerPoint >= legibleScale else { return }
        let rect = ImageCardLayout.captionRect(for: photo.frameStyle, in: size)
        let image = TextCardTypography.renderCaption(
            caption, overlay: ImageCardLayout.captionIsOverlaid(for: photo.frameStyle), size: rect.size,
            scale: min(pixelsPerPoint, 4), appearance: appearance
        )
        draw(image, in: rect, context: context)
    }

    private static func drawLink(
        _ web: WebPayload, size: CGSize, board: Board, context: CGContext, appearance: CanvasAppearance, pixelsPerPoint: CGFloat
    ) {
        let content = WebCardContent(payload: web, assets: board.assets, isLoading: false)
        let layout = WebCardLayout(content: content, width: size.width, appearance: appearance)
        let mesh = WebCardArt.meshImage(WebCardArt.meshColors(palette: content.palette, appearance: appearance, full: layout.fullMesh))
        context.saveGState()
        context.setAlpha(appearance.design.webMeshOpacity)
        draw(mesh, in: CGRect(origin: .zero, size: size), context: context)
        context.restoreGState()
        if let area = layout.image, let id = web.snapshot?.image {
            drawPicture(
                asset: id, crop: nil, in: area, cornerRadius: WebCardLayout.heroCornerRadius, board: board, context: context,
                placeholder: RGBA(hex: content.palette.darkMuted) ?? appearance.skeleton, pixelsPerPoint: pixelsPerPoint
            )
        }
        if let area = layout.image { drawPhotoMount(in: area, context: context, appearance: appearance) }
        if let area = layout.icon, let id = web.snapshot?.icon {
            drawPicture(
                asset: id, crop: nil, in: area, cornerRadius: layout.iconIsRound ? area.width / 2 : area.width * 0.24,
                board: board, context: context, placeholder: .clear, pixelsPerPoint: pixelsPerPoint
            )
        }
        guard pixelsPerPoint >= legibleScale else {
            drawBars(in: size, color: appearance.text.opacity(0.18), context: context, top: (layout.image?.maxY ?? 0) + 12)
            return
        }
        draw(WebCardTypography.render(layout, scale: min(pixelsPerPoint, 4)), in: CGRect(origin: .zero, size: size), context: context)
    }

    private static func drawPhotoMount(in rect: CGRect, context: CGContext, appearance: CanvasAppearance) {
        context.saveGState()
        context.addPath(ThemeArtwork.photoMount(in: rect, style: appearance.design.photoMount))
        context.setStrokeColor(appearance.captionInk.opacity(0.7).cgColor)
        context.setLineWidth(1.2)
        context.strokePath()
        context.restoreGState()
    }

    /// An asset decoded at about the size it's drawn, filling `area`.
    private static func drawPicture(
        asset id: AssetID, crop: Rect?, in area: CGRect, cornerRadius: CGFloat, board: Board, context: CGContext,
        placeholder: RGBA, pixelsPerPoint: CGFloat
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: area, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        context.clip()
        context.setFillColor(placeholder.cgColor)
        context.fill(area)
        let longSide = Int((max(area.width, area.height) * pixelsPerPoint * 1.5).rounded(.up))
        guard let asset = board.assets[id], longSide > 2,
              let image = ImageStore.decode(base64: asset.base64, maxLongSide: min(max(longSide, 32), 2048))?.image else { return }
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        let visible = ImageCardLayout.visibleCrop(crop: crop, imageAspect: aspect, photoSize: area.size)
        let pixelRect = ImageCardLayout.pixelRect(for: visible, imageSize: CGSize(width: image.width, height: image.height))
        draw(image.cropping(to: pixelRect) ?? image, in: area, context: context)
    }

    private static func drawBars(in size: CGSize, color: RGBA, context: CGContext, top: CGFloat = 18) {
        context.setFillColor(color.cgColor)
        var y = top
        for fraction in [0.8, 0.95, 0.6] where y + 10 < size.height - 8 {
            context.addPath(CGPath(
                roundedRect: CGRect(x: 16, y: y, width: (size.width - 32) * fraction, height: 9), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil
            ))
            y += 18
        }
        context.fillPath()
    }

    // MARK: Strings and pins

    private static func drawStrings(_ board: Board, in context: CGContext, appearance: CanvasAppearance) {
        let cards = Dictionary(board.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fans = CanvasGeometry.fanOffsets(for: board.strings)
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        for string in board.strings {
            guard let from = cards[string.from], let to = cards[string.to] else { continue }
            let curve = CanvasGeometry.stringCurve(
                from: CanvasGeometry.pinPoint(of: from), to: CanvasGeometry.pinPoint(of: to),
                sag: CGFloat(string.sag), fan: fans[string.id] ?? 0
            )
            let width = CGFloat(string.thickness * appearance.design.connection.widthScale + appearance.stringBoost)
            context.setLineWidth(width)
            switch string.stroke {
            case .solid: context.setLineDash(phase: 0, lengths: appearance.design.connection.dashPattern.map { $0 * width })
            case .dashed: context.setLineDash(phase: 0, lengths: [width * 3, width * 2.5])
            case .dotted: context.setLineDash(phase: 0, lengths: [0, width * 2.2])
            }
            context.setStrokeColor(appearance.gradient(for: string.color).from.cgColor)
            context.addPath(curve.path)
            context.strokePath()
            if let text = string.label, !text.isEmpty {
                let size = StringLabelStyle.capsuleSize(for: text, appearance: appearance)
                let middle = curve.point(at: 0.5)
                context.saveGState()
                context.translateBy(x: middle.x - size.width / 2, y: middle.y - size.height / 2)
                context.setLineDash(phase: 0, lengths: [])
                let bounds = CGRect(origin: .zero, size: size)
                let radius = ThemeArtwork.labelRadius(appearance.design.label, height: size.height)
                if appearance.design.label != .underline {
                    context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    context.setFillColor(appearance.labelFill.from.cgColor)
                    context.fillPath()
                }
                context.addPath(ThemeArtwork.labelDecoration(in: bounds, style: appearance.design.label))
                context.setLineWidth(0.8)
                context.setStrokeColor(appearance.labelText.opacity(0.7).cgColor)
                context.strokePath()
                let textRect = StringLabelStyle.textRect(in: size)
                draw(StringLabelStyle.render(text, size: textRect.size, scale: 2, appearance: appearance), in: textRect, context: context)
                context.restoreGState()
            }
        }
    }

    private static func drawPin(of card: Card, in context: CGContext, appearance: CanvasAppearance) {
        let point = CanvasGeometry.pinPoint(of: card)
        let colors = card.locked ? appearance.lockedPin : appearance.pin
        let radius: CGFloat = 7
        let head = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.saveGState()
        defer { context.restoreGState() }
        if appearance.design.fastener != .pushpin {
            let paths = ThemeArtwork.fastener(appearance.design.fastener, in: head)
            context.addPath(paths.body)
            context.setFillColor(colors.from.cgColor)
            context.fillPath()
            context.addPath(paths.detail)
            let ink = [.chalkCross, .paperclip].contains(appearance.design.fastener) ? colors.from : colors.to.mixed(with: .black, 0.4)
            context.setStrokeColor(ink.cgColor)
            context.setLineWidth(1.4)
            context.strokePath()
            return
        }
        context.addEllipse(in: head)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [colors.from.mixed(with: .white, 0.35).cgColor, colors.from.cgColor, colors.to.cgColor] as CFArray,
            locations: [0, 0.45, 1]
        ) {
            context.drawRadialGradient(
                gradient, startCenter: CGPoint(x: point.x - 2.5, y: point.y - 2.5), startRadius: 0,
                endCenter: point, endRadius: radius, options: [.drawsAfterEndLocation]
            )
        }
    }

    // MARK: Helpers

    private static func drawVertical(_ colors: GradientPair, in rect: CGRect, context: CGContext) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.cgColors as CFArray, locations: [0, 1]) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        context.restoreGState()
    }

    /// Draws `image` right side up in a context whose y axis points down.
    private static func draw(_ image: CGImage?, in rect: CGRect, context: CGContext) {
        guard let image else { return }
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }
}

public extension CanvasAppearance {
    /// The canvas tokens for a board's theme. Automatic picks Noir or Daylight.
    static func forTheme(_ theme: ThemeID, dark: Bool) -> CanvasAppearance {
        switch theme {
        case .system: dark ? .noir : .daylight
        case .noir: .noir
        case .cork: .cork
        case .blueprint: .blueprint
        case .daylight: .daylight
        case .parchment: .parchment
        case .chalkboard: .chalkboard
        case .fieldNotes: .fieldNotes
        case .crimeLab: .crimeLab
        case .circuit: .circuit
        case .scrapbook: .scrapbook
        case .newsroom: .newsroom
        case .observatory: .observatory
        }
    }
}
