import AppKit

/// Layout and drawing for the glass capsule that shows a string's label.
@MainActor
enum StringLabelStyle {
    static let height: CGFloat = 20
    static let fontSize: CGFloat = 11
    static let maxTextWidth: CGFloat = 220
    /// A dot in the string's color at the left of the capsule.
    static let dot: CGFloat = 6
    static let leading: CGFloat = 8
    static let gap: CGFloat = 5
    static let trailing: CGFloat = 10

    static func font(size: CGFloat = fontSize) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    static func attributes(appearance: CanvasAppearance, size: CGFloat = fontSize) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [.font: font(size: size), .foregroundColor: appearance.labelText.nsColor, .paragraphStyle: paragraph]
    }

    static func textWidth(_ text: String, appearance: CanvasAppearance) -> CGFloat {
        min(ceil(NSAttributedString(string: text, attributes: attributes(appearance: appearance)).size().width), maxTextWidth)
    }

    static func capsuleSize(for text: String, appearance: CanvasAppearance) -> CGSize {
        CGSize(width: leading + dot + gap + textWidth(text, appearance: appearance) + trailing, height: height)
    }

    /// Where the text sits inside a capsule of `size`.
    static func textRect(in size: CGSize) -> CGRect {
        let x = leading + dot + gap
        return CGRect(x: x, y: 0, width: max(size.width - x - trailing, 1), height: size.height)
    }

    /// The label's text, vertically centered in `size`, transparent elsewhere.
    static func render(_ text: String, size: CGSize, scale: CGFloat, appearance: CanvasAppearance) -> CGImage? {
        let attributed = NSAttributedString(string: text, attributes: attributes(appearance: appearance))
        let lineHeight = ceil(attributed.size().height)
        let rect = CGRect(x: 0, y: (size.height - lineHeight) / 2, width: size.width, height: lineHeight)
        return TextCardTypography.drawBitmap(size: size, scale: scale) {
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}
