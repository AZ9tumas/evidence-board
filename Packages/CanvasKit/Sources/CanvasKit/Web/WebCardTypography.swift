import AppKit
import BoardKit

/// Fonts and colors for web card text. Text sits on the card's mesh gradient, so its color is
/// chosen for contrast against the mesh (DESIGN.md §7.1, point 4).
struct WebCardTypography {
    let primary: NSColor
    let secondary: NSColor
    let tertiary: NSColor
    let accent: NSColor

    static let lightInk = RGBA(0xF2F4FA)
    static let darkInk = RGBA(0x15171C)

    /// `fullMesh` is true for compact and fallback cards, whose whole body is the palette's
    /// mesh; the others sit on the theme's card color with a hint of it.
    init(appearance: CanvasAppearance, palette: LinkPalette, fullMesh: Bool) {
        let backdrop = WebCardArt.meshBackdrop(palette: palette, appearance: appearance, full: fullMesh)
        let lightText = WebCardArt.prefersLightText(on: backdrop)
        let ink = lightText ? Self.lightInk : Self.darkInk
        primary = ink.nsColor
        secondary = ink.opacity(0.72).nsColor
        tertiary = ink.opacity(0.52).nsColor
        let vibrant = RGBA(hex: palette.vibrant) ?? appearance.selection.from
        accent = (lightText ? vibrant.mixed(with: .white, 0.45) : vibrant.mixed(with: .black, 0.35)).nsColor
    }

    private func paragraph(lineHeight: CGFloat = 1, singleLine: Bool = false, alignment: NSTextAlignment = .left) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        style.lineBreakMode = singleLine ? .byTruncatingTail : .byWordWrapping
        style.alignment = alignment
        return style
    }

    func title(_ text: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: primary,
            .paragraphStyle: paragraph(lineHeight: 1.08),
            .kern: -0.2,
        ])
    }

    /// The big title of compact cards ("Display 20 Bold").
    func display(_ text: String, size: CGFloat) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        return NSAttributedString(string: text, attributes: [
            .font: rounded,
            .foregroundColor: primary,
            .paragraphStyle: paragraph(lineHeight: 1.05),
            .kern: -0.3,
        ])
    }

    func body(_ text: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: secondary,
            .paragraphStyle: paragraph(lineHeight: 1.15),
        ])
    }

    func secondary(_ text: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: secondary,
            .paragraphStyle: paragraph(singleLine: true),
        ])
    }

    func tertiary(_ text: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: tertiary,
            .paragraphStyle: paragraph(singleLine: true),
        ])
    }

    /// A social post's text, set like a pull quote in New York.
    func quote(_ text: String, size: CGFloat) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: size)
        let serif = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«» ").union(.whitespacesAndNewlines))
        return NSAttributedString(string: "“\(trimmed)”", attributes: [
            .font: serif,
            .foregroundColor: primary,
            .paragraphStyle: paragraph(lineHeight: 1.18),
        ])
    }

    /// "THE VERGE · theverge.com", or just the domain.
    func siteLine(site: String?, domain: String) -> NSAttributedString {
        let line = NSMutableAttributedString()
        let style = paragraph(singleLine: true)
        if let site, !site.isEmpty, site.lowercased() != domain.lowercased() {
            line.append(NSAttributedString(string: site.uppercased(), attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
                .foregroundColor: secondary,
                .kern: 0.6,
                .paragraphStyle: style,
            ]))
            line.append(NSAttributedString(string: "  ·  ", attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: tertiary, .paragraphStyle: style]))
        }
        line.append(NSAttributedString(string: domain, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: tertiary,
            .paragraphStyle: style,
        ]))
        return line
    }

    func openHint() -> NSAttributedString {
        NSAttributedString(string: "↗ Open", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: accent,
            .paragraphStyle: paragraph(singleLine: true, alignment: .right),
        ])
    }

    /// Duration on video cards: white on a dark capsule.
    func badge(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
    }

    /// Draws every text block of `layout`, transparent elsewhere.
    @MainActor
    static func render(_ layout: WebCardLayout, scale: CGFloat) -> CGImage? {
        guard !layout.blocks.isEmpty else { return nil }
        return TextCardTypography.drawBitmap(size: layout.size, scale: scale) {
            for block in layout.blocks {
                block.text.draw(with: block.frame, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
            }
        }
    }
}
