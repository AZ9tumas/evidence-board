import Foundation
import CoreGraphics
import BoardKit

/// Shared vector artwork for the live canvas, Quick Look and thumbnails.
enum ThemeArtwork {
    static func outline(_ rect: CGRect, card: Card, appearance: CanvasAppearance) -> CGPath {
        let design = appearance.design
        let path = CGMutablePath()
        switch design.edge {
        case .standard, .rounded:
            let radius = design.edge == .standard ? CanvasGeometry.cornerRadius(of: card) : CGFloat(design.cornerRadius)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .square:
            return CGPath(rect: rect, transform: nil)
        case .clipped:
            let cut = min(CGFloat(design.cornerRadius), min(rect.width, rect.height) / 4)
            path.addLines(between: [CGPoint(x: rect.minX + cut, y: rect.minY), CGPoint(x: rect.maxX - cut, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + cut), CGPoint(x: rect.maxX, y: rect.maxY - cut),
                CGPoint(x: rect.maxX - cut, y: rect.maxY), CGPoint(x: rect.minX + cut, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY - cut), CGPoint(x: rect.minX, y: rect.minY + cut)])
        case .deckled, .ticket:
            let box = rect.insetBy(dx: 2, dy: 2)
            let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            var random = SplitMix(seed: 0xDE_C1E)
            for index in 0..<4 {
                let a = corners[index], b = corners[(index + 1) % 4]
                let count = max(1, Int(hypot(b.x - a.x, b.y - a.y) / 9))
                if index == 0 { path.move(to: a) }
                for step in 1...count {
                    let t = CGFloat(step) / CGFloat(count)
                    let inset = design.edge == .ticket ? (step % 2 == 0 ? 0.0 : 2.0) : random.next(in: -1.4...1.4)
                    let dx: CGFloat = index == 1 ? -1 : (index == 3 ? 1 : 0)
                    let dy: CGFloat = index == 0 ? 1 : (index == 2 ? -1 : 0)
                    path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t + dx * inset,
                                            y: a.y + (b.y - a.y) * t + dy * inset))
                }
            }
        }
        path.closeSubpath()
        return path
    }

    static func ornament(in rect: CGRect, style: CardOrnament) -> CGPath {
        let path = CGMutablePath()
        let box = rect.insetBy(dx: 7, dy: 7)
        guard box.width > 0, box.height > 0 else { return path }
        func line(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
        switch style {
        case .none: break
        case .archival:
            path.addRect(box)
            for x in [box.minX + 4, box.maxX - 4] {
                line(CGPoint(x: x, y: box.minY), CGPoint(x: x, y: box.minY + 12))
                line(CGPoint(x: x, y: box.maxY - 12), CGPoint(x: x, y: box.maxY))
            }
        case .chalk:
            path.addRect(box)
            path.addRect(box.insetBy(dx: 2.5, dy: 2.5))
        case .ruled:
            for y in stride(from: 53.0, to: rect.maxY - 16, by: 24) {
                line(CGPoint(x: 12, y: y), CGPoint(x: rect.maxX - 12, y: y))
            }
            line(CGPoint(x: 12, y: 28), CGPoint(x: 12, y: rect.maxY - 12))
            for x in [26.0, rect.midX, rect.maxX - 26] { path.addEllipse(in: CGRect(x: x - 2, y: 12, width: 4, height: 4)) }
        case .specimen:
            for x in stride(from: max(18, rect.maxX - 67), to: rect.maxX - 16, by: 3) {
                line(CGPoint(x: x, y: 10), CGPoint(x: x, y: CGFloat(23 - (Int(x) % 3))))
            }
            for y in stride(from: 36.0, to: rect.maxY - 16, by: 8) {
                line(CGPoint(x: 6, y: y), CGPoint(x: Int(y) % 16 == 0 ? 12 : 9, y: y))
            }
            line(CGPoint(x: 18, y: rect.maxY - 8), CGPoint(x: rect.maxX - 18, y: rect.maxY - 8))
        case .circuit:
            for (x, dx) in [(box.minX, 1.0), (box.maxX, -1.0)] {
                for (y, dy) in [(box.minY, 1.0), (box.maxY, -1.0)] {
                    path.move(to: CGPoint(x: x, y: y + 21 * dy))
                    path.addLine(to: CGPoint(x: x, y: y + 7 * dy))
                    path.addLine(to: CGPoint(x: x + 7 * dx, y: y))
                    path.addLine(to: CGPoint(x: x + 21 * dx, y: y))
                    path.addEllipse(in: CGRect(x: x + 24 * dx - 2, y: y - 2, width: 4, height: 4))
                }
            }
        case .stitching:
            for x in stride(from: box.minX, to: box.maxX - 4, by: 9) {
                line(CGPoint(x: x, y: box.minY), CGPoint(x: x + 4, y: box.minY))
                line(CGPoint(x: x, y: box.maxY), CGPoint(x: x + 4, y: box.maxY))
            }
            for y in stride(from: box.minY, to: box.maxY - 4, by: 9) {
                line(CGPoint(x: box.minX, y: y), CGPoint(x: box.minX, y: y + 4))
                line(CGPoint(x: box.maxX, y: y), CGPoint(x: box.maxX, y: y + 4))
            }
        case .newspaper:
            for y in [21.0, 24.0, rect.maxY - 10, rect.maxY - 13] {
                line(CGPoint(x: 12, y: y), CGPoint(x: rect.maxX - 12, y: y))
            }
        case .celestial:
            for x in [15.0, rect.maxX - 15] {
                for y in [15.0, rect.maxY - 15] {
                    line(CGPoint(x: x - 4, y: y), CGPoint(x: x + 4, y: y))
                    line(CGPoint(x: x, y: y - 4), CGPoint(x: x, y: y + 4))
                }
            }
            path.addRoundedRect(in: box, cornerWidth: 18, cornerHeight: 18)
        }
        return path
    }

    static func photoMount(in rect: CGRect, style: PhotoMount) -> CGPath {
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return path }
        let box = rect.insetBy(dx: 3, dy: 3)
        switch style {
        case .standard: break
        case .etched, .doubleRule, .chalk:
            path.addRect(box)
            path.addRect(box.insetBy(dx: style == .chalk ? 2 : 4, dy: style == .chalk ? 2 : 4))
        case .rounded:
            path.addRoundedRect(in: box, cornerWidth: 12, cornerHeight: 12)
        case .film:
            for y in stride(from: box.minY + 3, to: box.maxY - 7, by: 13) {
                for x in [box.minX, box.maxX - 5] { path.addRect(CGRect(x: x, y: y, width: 5, height: 7)) }
            }
        case .brackets, .corners, .tape:
            let side = min(15, min(box.width, box.height) / 4)
            for (x, dx) in [(box.minX, 1.0), (box.maxX, -1.0)] {
                for (y, dy) in [(box.minY, 1.0), (box.maxY, -1.0)] {
                    path.move(to: CGPoint(x: x + side * dx, y: y))
                    path.addLine(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + side * dy))
                    if style == .corners { path.closeSubpath() }
                    if style == .tape {
                        path.move(to: CGPoint(x: x + side * dx, y: y))
                        path.addLine(to: CGPoint(x: x, y: y + side * dy))
                    }
                }
            }
        }
        return path
    }

    static func fastener(_ style: BoardFastener, in rect: CGRect) -> (body: CGPath, detail: CGPath) {
        let body = CGMutablePath(), detail = CGMutablePath()
        let cx = rect.midX, cy = rect.midY
        func line(_ a: CGPoint, _ b: CGPoint) { detail.move(to: a); detail.addLine(to: b) }
        switch style {
        case .pushpin, .screw, .button:
            body.addEllipse(in: rect)
            if style == .screw { line(CGPoint(x: cx - 4, y: cy - 4), CGPoint(x: cx + 4, y: cy + 4)) }
            if style == .button {
                for x in [cx - 2, cx + 2] { for y in [cy - 2, cy + 2] {
                    detail.addEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
                } }
                detail.addEllipse(in: rect.insetBy(dx: 2, dy: 2))
            }
        case .waxSeal, .star:
            let count = style == .star ? 10 : 24
            for i in 0..<count {
                let angle = Double(i) * .pi * 2 / Double(count) - .pi / 2
                let radius = rect.width / 2 * (i % 2 == 0 ? 1 : (style == .star ? 0.45 : 0.88))
                let point = CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)
                if i == 0 { body.move(to: point) } else { body.addLine(to: point) }
            }
            body.closeSubpath()
            if style == .waxSeal { detail.addEllipse(in: rect.insetBy(dx: 3, dy: 3)) }
        case .chalkCross:
            line(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
            line(CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY))
        case .tape:
            body.addLines(between: [CGPoint(x: cx - 14, y: cy - 4), CGPoint(x: cx + 13, y: cy - 6),
                CGPoint(x: cx + 14, y: cy + 4), CGPoint(x: cx - 13, y: cy + 6)])
            body.closeSubpath()
            line(CGPoint(x: cx - 9, y: cy - 2), CGPoint(x: cx + 9, y: cy - 3))
        case .solder:
            body.addRect(rect)
            detail.addEllipse(in: rect.insetBy(dx: 3, dy: 3))
            line(CGPoint(x: rect.minX - 3, y: cy), CGPoint(x: rect.maxX + 3, y: cy))
        case .paperclip:
            detail.addRoundedRect(in: rect.insetBy(dx: 3, dy: -3), cornerWidth: 4, cornerHeight: 4)
            detail.addRoundedRect(in: rect.insetBy(dx: 5, dy: -1), cornerWidth: 2, cornerHeight: 2)
        }
        return (body, detail)
    }

    static func labelRadius(_ style: ConnectionLabel, height: CGFloat) -> CGFloat {
        switch style {
        case .capsule: height / 2
        case .rounded: 6
        case .tag, .ticket: 2
        default: 0
        }
    }

    static func labelDecoration(in rect: CGRect, style: ConnectionLabel) -> CGPath {
        let path = CGMutablePath()
        func line(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
        switch style {
        case .underline:
            line(CGPoint(x: 4, y: rect.maxY - 1), CGPoint(x: rect.maxX - 4, y: rect.maxY - 1))
        case .bracket:
            for (x, dx) in [(2.0, 1.0), (rect.maxX - 2, -1.0)] {
                path.addLines(between: [CGPoint(x: x + 4 * dx, y: 2), CGPoint(x: x, y: 2),
                                       CGPoint(x: x, y: rect.maxY - 2), CGPoint(x: x + 4 * dx, y: rect.maxY - 2)])
            }
        case .tag:
            path.addEllipse(in: CGRect(x: 5, y: rect.midY - 2, width: 4, height: 4))
        case .ticket:
            for y in stride(from: 3.0, to: rect.maxY, by: 4) {
                for x in [3.0, rect.maxX - 3] { line(CGPoint(x: x, y: y), CGPoint(x: x, y: y + 1)) }
            }
        case .plaque:
            path.addRect(rect.insetBy(dx: 2, dy: 2))
        default: break
        }
        return path
    }

    /// A seeded, seamless board surface. Generated once per style/color/backing scale.
    static func surfaceTile(_ texture: BoardTexture, color: RGBA, scale: CGFloat) -> CGImage? {
        if texture == .grain { return GrainTexture.makeTile(color: color, scale: scale) }
        let side: CGFloat = 256
        let pixels = Int(side * scale)
        guard pixels > 0, let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(0.7)
        var random = SplitMix(seed: 0xB04D)
        func line(_ a: CGPoint, _ b: CGPoint) { context.move(to: a); context.addLine(to: b); context.strokePath() }
        switch texture {
        case .dots:
            for x in stride(from: 0.0, to: side, by: 32) { for y in stride(from: 0.0, to: side, by: 32) {
                context.fillEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
            } }
        case .lines, .tiles:
            let pitch: CGFloat = texture == .tiles ? 64 : 32
            for value in stride(from: 0.0, through: side, by: pitch) {
                line(CGPoint(x: value, y: 0), CGPoint(x: value, y: side))
                line(CGPoint(x: 0, y: value), CGPoint(x: side, y: value))
                if texture == .tiles {
                    context.setLineWidth(2)
                    line(CGPoint(x: value + 2, y: 0), CGPoint(x: value + 2, y: side))
                    context.setLineWidth(0.7)
                }
            }
        case .ruled:
            for y in stride(from: 0.0, to: side, by: 32) { line(CGPoint(x: 0, y: y), CGPoint(x: side, y: y)) }
            context.setStrokeColor(color.opacity(min(color.alpha * 1.8, 1)).cgColor)
            line(CGPoint(x: 32, y: 0), CGPoint(x: 32, y: side))
            line(CGPoint(x: 35, y: 0), CGPoint(x: 35, y: side))
        case .circuit:
            for index in 0..<12 {
                let x = CGFloat(index % 4) * 64 + 12, y = CGFloat(index / 4) * 80 + 12
                let rise = CGFloat(random.next(in: 12...26))
                context.move(to: CGPoint(x: x, y: y))
                context.addLine(to: CGPoint(x: x + 18, y: y))
                context.addLine(to: CGPoint(x: x + 30, y: y + rise))
                context.addLine(to: CGPoint(x: x + 30, y: y + 52))
                context.strokePath()
                context.strokeEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
                context.fillEllipse(in: CGRect(x: x + 28, y: y + 50, width: 4, height: 4))
            }
        case .linen:
            for i in stride(from: 0.0, to: side, by: 4) {
                context.setLineWidth(Int(i) % 8 == 0 ? 1 : 0.4)
                line(CGPoint(x: i, y: 0), CGPoint(x: i, y: side))
                line(CGPoint(x: 0, y: i + 1), CGPoint(x: side, y: i + 1))
            }
        case .newsprint:
            for column in 0..<4 {
                let x = CGFloat(column) * 64 + 5
                context.setLineWidth(0.6)
                for y in stride(from: 8.0, to: side - 4, by: 5) {
                    let width = CGFloat(random.next(in: 22...52))
                    line(CGPoint(x: x, y: y), CGPoint(x: x + width, y: y))
                }
                context.setLineWidth(2)
                line(CGPoint(x: x, y: 3), CGPoint(x: x + 50, y: 3))
            }
        case .stars:
            for _ in 0..<35 {
                let x = random.next(in: 0...256), y = random.next(in: 0...256)
                context.fillEllipse(in: CGRect(x: x, y: y, width: 1.8, height: 1.8))
            }
            context.setLineDash(phase: 0, lengths: [3, 5])
            for radius in [42.0, 84.0, 120.0] {
                context.strokeEllipse(in: CGRect(x: 128 - radius, y: 128 - radius, width: radius * 2, height: radius * 2))
            }
            context.setLineDash(phase: 0, lengths: [])
            line(CGPoint(x: 38, y: 60), CGPoint(x: 78, y: 85))
            line(CGPoint(x: 78, y: 85), CGPoint(x: 101, y: 47))
        case .paper, .chalk:
            for _ in 0..<(texture == .paper ? 900 : 1600) {
                let x = random.next(in: 0...256), y = random.next(in: 0...256)
                let length = random.next(in: texture == .paper ? 1...7 : 0.4...2.5)
                context.setStrokeColor(color.opacity(color.alpha * random.next(in: 0.2...1)).cgColor)
                line(CGPoint(x: x, y: y), CGPoint(x: x + length, y: y + random.next(in: -1...1)))
            }
            if texture == .chalk {
                context.setLineWidth(8)
                context.setStrokeColor(color.opacity(color.alpha * 0.15).cgColor)
                for y in stride(from: 22.0, to: side, by: 48) { line(CGPoint(x: 15, y: y), CGPoint(x: 230, y: y + 7)) }
            }
        case .grain: break // handled above
        }
        return context.makeImage()
    }
}
