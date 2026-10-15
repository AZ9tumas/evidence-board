import AppKit
import BoardKit

/// Fonts, colors and layout for text cards.
///
/// The bitmap renderer and the live editor both take their attributes from here, so going
/// into edit mode doesn't move a single line.
@MainActor
enum TextCardTypography {
    /// Space between the card edge and its text. The top clears the pin.
    static let insets = NSEdgeInsets(top: 30, left: 18, bottom: 18, right: 18)
    static let defaultWidth: CGFloat = 260
    static let minimumSize = CGSize(width: 120, height: 64)

    static func font(for style: TextCardStyle) -> NSFont {
        switch style {
        case .note: .systemFont(ofSize: 15)
        case .headline: .systemFont(ofSize: 28, weight: .bold)
        case .typewriter: .monospacedSystemFont(ofSize: 14, weight: .regular)
        }
    }

    static func textColor(for style: TextCardStyle, appearance: CanvasAppearance) -> NSColor {
        (style == .typewriter ? appearance.paperText : appearance.text).nsColor
    }

    /// The attributes for unformatted text, also used while typing.
    static func baseAttributes(
        style: TextCardStyle, alignment: TextCardAlignment, appearance: CanvasAppearance
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        paragraph.lineHeightMultiple = style == .headline ? 1.05 : 1.25
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: font(for: style),
            .foregroundColor: textColor(for: style, appearance: appearance),
            .paragraphStyle: paragraph,
            .kern: style == .headline ? -0.4 : 0,
        ]
    }

    /// The card's text with `**bold**`, `*italic*`, `` `code` `` and `~~strike~~` applied.
    static func attributedText(for text: TextPayload, appearance: CanvasAppearance) -> NSAttributedString {
        let base = baseAttributes(style: text.style, alignment: text.alignment, appearance: appearance)
        let plain = NSAttributedString(string: text.content, attributes: base)
        guard text.content.contains(where: { "*_`~".contains($0) }),
              let parsed = try? AttributedString(
                markdown: text.content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
              )
        else { return plain }

        let baseFont = font(for: text.style)
        let styled = NSMutableAttributedString(string: String(parsed.characters), attributes: base)
        for run in parsed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            let range = NSRange(run.range, in: parsed)
            var runFont = baseFont
            if intent.contains(.code) {
                runFont = .monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .medium)
                styled.addAttribute(.foregroundColor, value: appearance.codeText.nsColor, range: range)
            }
            var traits = runFont.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if traits != runFont.fontDescriptor.symbolicTraits {
                runFont = NSFont(descriptor: runFont.fontDescriptor.withSymbolicTraits(traits), size: runFont.pointSize) ?? runFont
            }
            styled.addAttribute(.font, value: runFont, range: range)
            if intent.contains(.strikethrough) {
                styled.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        return styled
    }

    /// The card height that fits `text` at `width`, used while the card's height is automatic.
    static func fittingHeight(for text: TextPayload, width: CGFloat, appearance: CanvasAppearance) -> CGFloat {
        let textWidth = max(width - insets.left - insets.right, 1)
        var attributed = attributedText(for: text, appearance: appearance)
        if attributed.length == 0 {
            // An empty card is still one line tall.
            attributed = NSAttributedString(
                string: " ", attributes: baseAttributes(style: text.style, alignment: text.alignment, appearance: appearance)
            )
        }
        let measured = attributed.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        return max(ceil(measured) + insets.top + insets.bottom, minimumSize.height)
    }

    /// Draws the card's text, transparent everywhere else, at `scale` pixels per point.
    static func render(_ text: TextPayload, size: CGSize, scale: CGFloat, appearance: CanvasAppearance) -> CGImage? {
        let textRect = CGRect(
            x: insets.left, y: insets.top,
            width: max(size.width - insets.left - insets.right, 1),
            height: max(size.height - insets.top - insets.bottom, 1)
        )
        let attributed = attributedText(for: text, appearance: appearance)
        return drawBitmap(size: size, scale: scale) {
            attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        }
    }

    // MARK: Captions

    /// New York italic, as in DESIGN.md §6.3.
    static func captionFont(size: CGFloat = 13) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        let serif = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return NSFont(descriptor: serif.withSymbolicTraits(.italic), size: size) ?? base
    }

    /// Ink on paper for polaroids; white with a soft shadow when laid over the photo.
    static func captionAttributes(overlay: Bool, appearance: CanvasAppearance, size: CGFloat = 13) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = overlay ? .left : .center
        paragraph.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: captionFont(size: size),
            .foregroundColor: overlay ? NSColor.white.withAlphaComponent(0.95) : appearance.captionInk.nsColor,
            .paragraphStyle: paragraph,
        ]
        if overlay {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            attributes[.shadow] = shadow
        }
        return attributes
    }

    /// One line of caption, vertically centered in `size`.
    static func renderCaption(
        _ caption: String, overlay: Bool, size: CGSize, scale: CGFloat, appearance: CanvasAppearance
    ) -> CGImage? {
        let attributed = NSAttributedString(string: caption, attributes: captionAttributes(overlay: overlay, appearance: appearance))
        let lineHeight = ceil(attributed.size().height)
        let rect = CGRect(x: 0, y: max((size.height - lineHeight) / 2, 0), width: size.width, height: lineHeight)
        return drawBitmap(size: size, scale: scale) {
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    // MARK: Drawing

    /// A transparent bitmap of `size` points at `scale`, with AppKit drawing set up top-down so
    /// row 0 of the bitmap is the top.
    static func drawBitmap(size: CGSize, scale: CGFloat, _ draw: () -> Void) -> CGImage? {
        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth * pixelHeight <= 32_000_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

extension RGBA {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
