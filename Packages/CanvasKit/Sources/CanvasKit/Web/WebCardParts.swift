import AppKit
import QuartzCore
import BoardKit

/// The layers only web cards have: ambient glow, mesh gradient, favicon, play button,
/// duration badge and the loading shimmer (DESIGN.md §7.1, §7.5). `CardNode` owns one per
/// web card and places it with a `WebCardLayout`.
@MainActor
final class WebCardParts {
    /// A blurred copy of the hero behind the card, bleeding onto the board.
    let glow = CALayer()
    let mesh = CALayer()
    let icon = CALayer()
    let play = CALayer()
    private let playGlyph = CAShapeLayer()
    let badge = CALayer()
    /// The sweep across the skeleton bars while the preview loads.
    let shimmer = CAGradientLayer()

    private(set) var iconImage: CGImage?
    var requestedIconSide: Int?
    private var meshKey: [RGBA] = []
    private var glowSource: CGImage?

    init() {
        glow.opacity = 0.35
        glow.isHidden = true
        glow.contentsGravity = .resize
        mesh.contentsGravity = .resize
        mesh.magnificationFilter = .linear
        icon.masksToBounds = true
        icon.cornerCurve = .continuous
        icon.contentsGravity = .resizeAspectFill
        play.backgroundColor = RGBA.white.opacity(0.2).cgColor
        play.borderColor = RGBA.white.opacity(0.55).cgColor
        play.borderWidth = 1
        play.shadowColor = RGBA.black.cgColor
        play.shadowOpacity = 0.35
        play.shadowRadius = 8
        play.shadowOffset = CGSize(width: 0, height: 3)
        playGlyph.fillColor = RGBA.white.opacity(0.95).cgColor
        playGlyph.lineJoin = .round
        play.addSublayer(playGlyph)
        badge.backgroundColor = RGBA.black.opacity(0.6).cgColor
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmer.colors = [RGBA.white.opacity(0).cgColor, RGBA.white.opacity(0.09).cgColor, RGBA.white.opacity(0).cgColor]
    }

    /// Places everything for `layout` on a card of `bounds`.
    func apply(_ layout: WebCardLayout, content: WebCardContent, bounds: CGRect, appearance: CanvasAppearance) {
        let colors = WebCardArt.meshColors(palette: content.palette, appearance: appearance, full: layout.fullMesh)
        if colors != meshKey {
            meshKey = colors
            mesh.contents = WebCardArt.meshImage(colors)
        }
        mesh.frame = bounds

        // The glow is 15% larger than the card and sits a little low, like light from below.
        // Its bitmap carries a transparent margin for the blur to fade into.
        let reach = 1.15 * (1 + 2 * WebCardArt.glowMargin)
        let glowSize = CGSize(width: bounds.width * reach, height: bounds.height * reach)
        glow.frame = CGRect(
            x: bounds.midX - glowSize.width / 2, y: bounds.midY - glowSize.height / 2 + 12,
            width: glowSize.width, height: glowSize.height
        )

        if let frame = layout.icon {
            icon.frame = frame
            icon.cornerRadius = layout.iconIsRound ? frame.width / 2 : frame.width * 0.24
            icon.backgroundColor = (RGBA(hex: content.palette.light) ?? .white).opacity(0.92).cgColor
            icon.borderWidth = 0.5
            icon.borderColor = RGBA.white.opacity(0.25).cgColor
        }

        if let frame = layout.playButton {
            play.frame = frame
            play.cornerRadius = frame.width / 2
            play.shadowPath = CGPath(ellipseIn: CGRect(origin: .zero, size: frame.size), transform: nil)
            playGlyph.frame = CGRect(origin: .zero, size: frame.size)
            playGlyph.path = WebCardArt.playTriangle(in: CGRect(origin: .zero, size: frame.size))
        }
        if let frame = layout.durationBadge {
            badge.frame = frame
            badge.cornerRadius = frame.height / 2
        }
    }

    /// The bars shown while loading, with the shimmer over them.
    func skeletonLayers(for layout: WebCardLayout, bounds: CGRect, appearance: CanvasAppearance) -> [CALayer] {
        let bar = appearance.skeleton
        var layers: [CALayer] = layout.skeletonBars.enumerated().map { index, frame in
            let layer = CALayer()
            layer.frame = frame
            layer.backgroundColor = (index == 0 ? bar.opacity(bar.alpha * 2) : bar).cgColor
            layer.cornerRadius = index == 0 ? WebCardLayout.heroCornerRadius : frame.height / 2
            layer.cornerCurve = .continuous
            return layer
        }
        let sheen = appearance.hasLightCards ? 0.55 : 0.09
        shimmer.colors = [RGBA.white.opacity(0).cgColor, RGBA.white.opacity(sheen).cgColor, RGBA.white.opacity(0).cgColor]
        shimmer.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width, height: bounds.height)
        if shimmer.animation(forKey: "sweep") == nil, !Motion.isReduced {
            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = -bounds.width / 2
            sweep.toValue = bounds.width * 1.5
            sweep.duration = 1.2
            sweep.repeatCount = .infinity
            shimmer.add(sweep, forKey: "sweep")
        }
        layers.append(shimmer)
        return layers
    }

    /// The decoded hero: feeds the glow, and the avatar on social posts that use it as one.
    func setHero(_ image: CGImage?, usesAsAvatar: Bool) {
        if let image, image !== glowSource {
            glowSource = image
            glow.contents = WebCardArt.glowImage(from: image)
        } else if image == nil {
            glowSource = nil
            glow.contents = nil
        }
        if usesAsAvatar { icon.contents = image ?? iconImage }
    }

    func setIcon(_ image: CGImage?, usesHeroAsAvatar: Bool) {
        iconImage = image
        if !usesHeroAsAvatar { icon.contents = image }
    }

    /// A letter on the palette's color, for cards whose page has no usable icon.
    func setMonogram(for content: WebCardContent, side: CGFloat, scale: CGFloat) {
        guard iconImage == nil, let letter = content.domain.first(where: \.isLetter) else { return }
        let fill = RGBA(hex: content.palette.vibrant) ?? .white
        let ink = WebCardArt.prefersLightText(on: fill) ? NSColor.white : NSColor.black
        let text = NSAttributedString(string: String(letter).uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: side * 0.52, weight: .bold),
            .foregroundColor: ink,
        ])
        let size = CGSize(width: side, height: side)
        icon.contents = TextCardTypography.drawBitmap(size: size, scale: scale) {
            fill.nsColor.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let measured = text.size()
            text.draw(at: CGPoint(x: (side - measured.width) / 2, y: (side - measured.height) / 2))
        }
    }

    func discardImages() {
        iconImage = nil
        requestedIconSide = nil
        glowSource = nil
        glow.contents = nil
        icon.contents = nil
    }
}
