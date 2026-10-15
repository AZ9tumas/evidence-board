import AppKit
import CoreImage
import BoardKit

/// The pictures behind a web card's text: its mesh gradient, the blurred ambient glow, the
/// play button (DESIGN.md §7.1).
enum WebCardArt {
    static func color(_ hex: String, fallback: RGBA) -> RGBA {
        RGBA(hex: hex) ?? fallback
    }

    /// The nine colors of a 3×3 mesh, row by row. Compact and fallback cards get a vivid mesh
    /// from the page's palette; the others keep the theme's card color with a hint of it.
    static func meshColors(palette: LinkPalette, appearance: CanvasAppearance, full: Bool) -> [RGBA] {
        let card = appearance.cardFill
        let vibrant = color(palette.vibrant, fallback: appearance.selection.from)
        let muted = color(palette.muted, fallback: card.from)
        let darkVibrant = color(palette.darkVibrant, fallback: card.from)
        let darkMuted = color(palette.darkMuted, fallback: card.to)
        if full {
            return [
                darkVibrant, vibrant.mixed(with: darkVibrant, 0.45), muted.mixed(with: darkMuted, 0.35),
                darkMuted.mixed(with: vibrant, 0.18), darkVibrant.mixed(with: vibrant, 0.3), darkMuted,
                darkMuted, darkMuted.mixed(with: darkVibrant, 0.45), darkVibrant.mixed(with: .black, 0.35),
            ]
        }
        return [
            card.from.mixed(with: darkVibrant, 0.35), card.from, card.from.mixed(with: muted, 0.3),
            card.to.mixed(with: darkMuted, 0.4), card.to.mixed(with: vibrant, 0.06), card.to.mixed(with: darkVibrant, 0.3),
            darkMuted.mixed(with: card.to, 0.45), card.to.mixed(with: muted, 0.18), darkVibrant.mixed(with: card.to, 0.5),
        ]
    }

    /// The color text mostly sits on: the middle and bottom of the mesh.
    static func meshBackdrop(palette: LinkPalette, appearance: CanvasAppearance, full: Bool) -> RGBA {
        let colors = meshColors(palette: palette, appearance: appearance, full: full)
        let lower = Array(colors[3...])
        let count = Double(lower.count)
        return RGBA(
            red: lower.map(\.red).reduce(0, +) / count,
            green: lower.map(\.green).reduce(0, +) / count,
            blue: lower.map(\.blue).reduce(0, +) / count
        )
    }

    /// WCAG relative luminance.
    static func luminance(_ color: RGBA) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Light text unless dark text reads clearly better (WCAG contrast, §7.1).
    static func prefersLightText(on background: RGBA) -> Bool {
        contrast(.white, background) >= min(contrast(RGBA(0x15171C), background), 4.5)
    }

    /// A small bitmap of a 3×3 mesh with smooth (smoothstep) blending. Shown stretched over the
    /// card with linear filtering, it reads as a soft mesh gradient at any size.
    static func meshImage(_ colors: [RGBA], side: Int = 32) -> CGImage? {
        guard colors.count == 9, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ), let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        for y in 0..<side {
            for x in 0..<side {
                // Row 0 of the bitmap is the bottom of the image.
                let u = Double(x) / Double(side - 1) * 2
                let v = (1 - Double(y) / Double(side - 1)) * 2
                let column = min(Int(u), 1), row = min(Int(v), 1)
                let fu = smooth(u - Double(column)), fv = smooth(v - Double(row))
                let c00 = colors[row * 3 + column], c10 = colors[row * 3 + column + 1]
                let c01 = colors[(row + 1) * 3 + column], c11 = colors[(row + 1) * 3 + column + 1]
                func mix(_ key: KeyPath<RGBA, Double>) -> UInt8 {
                    let top = c00[keyPath: key] * (1 - fu) + c10[keyPath: key] * fu
                    let bottom = c01[keyPath: key] * (1 - fu) + c11[keyPath: key] * fu
                    return UInt8(min(max((top * (1 - fv) + bottom * fv) * 255, 0), 255).rounded())
                }
                let offset = (y * side + x) * 4
                pixels[offset] = mix(\.red)
                pixels[offset + 1] = mix(\.green)
                pixels[offset + 2] = mix(\.blue)
                pixels[offset + 3] = 255
            }
        }
        return context.makeImage()
    }

    @MainActor private static let blurContext = CIContext(options: [.cacheIntermediates: false])

    /// How far the glow bitmap reaches past the picture it's made from, as a fraction of its
    /// size on each side. The blur fades to nothing in this margin, so the glow has no edges.
    static let glowMargin: CGFloat = 0.3

    /// A heavily blurred, small copy of `image` for the glow behind the card, with a
    /// transparent margin of `glowMargin` around it.
    @MainActor
    static func glowImage(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let scale = 64 / max(input.extent.width, input.extent.height, 1)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let size = small.extent.size
        let canvas = CGRect(
            x: -size.width * glowMargin, y: -size.height * glowMargin,
            width: size.width * (1 + 2 * glowMargin), height: size.height * (1 + 2 * glowMargin)
        )
        let blurred = small
            .transformed(by: CGAffineTransform(translationX: -small.extent.minX, y: -small.extent.minY))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: min(size.width, size.height) * 0.16])
            .cropped(to: canvas)
        return blurContext.createCGImage(blurred, from: canvas)
    }

    /// A rounded triangle pointing right, for the play button.
    static func playTriangle(in rect: CGRect) -> CGPath {
        let side = rect.width * 0.36
        let center = CGPoint(x: rect.midX + side * 0.12, y: rect.midY)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - side / 2, y: center.y - side * 0.58))
        path.addLine(to: CGPoint(x: center.x + side * 0.6, y: center.y))
        path.addLine(to: CGPoint(x: center.x - side / 2, y: center.y + side * 0.58))
        path.closeSubpath()
        return path
    }
}
