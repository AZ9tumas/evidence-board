#if DEBUG
import AppKit
import BoardKit
import LinkPreviewKit

/// Made-up pages with generated pictures, one for each web card layout, so every variant can
/// be seen without a network (Debug menu, snapshot workflow).
enum TestLinks {
    struct Sample: Sendable {
        var url: URL
        /// `nil` for a card that stays loading.
        var preview: LinkPreview?
        var assets = WebPreviewAssets()
    }

    static func make(at date: Date = .now) -> [Sample] {
        let published = Date(timeIntervalSince1970: 1_791_100_800) // Oct 4, 2026
        var samples: [Sample] = []

        func add(
            _ address: String, _ variant: LinkVariant, title: String, description: String? = nil, site: String? = nil,
            author: String? = nil, publishedAt: Date? = nil, duration: Double? = nil,
            image: CGImage? = nil, icon: CGImage? = nil
        ) {
            let url = URL(string: address)!
            let imported = WebPreviewAssets(
                image: image.flatMap { try? ImageImporter.encode($0, opaque: true) },
                icon: icon.flatMap { try? ImageImporter.encode($0, opaque: true) }
            )
            let palette = (image ?? icon).flatMap { ImageProbe.palette(of: $0) }
                ?? PaletteExtractor.palette(forDomain: LinkURL.displayHost(of: url))
            let preview = LinkPreview(
                url: url, fetchedAt: date, variant: variant, title: title, pageDescription: description, siteName: site,
                author: author, publishedAt: publishedAt, duration: duration, palette: palette
            )
            samples.append(Sample(url: url, preview: preview, assets: imported))
        }

        add(
            "https://www.harborgazette.com/2026/10/04/ferry-left-early", .hero,
            title: "Night ferry left eleven minutes early, harbor logs show",
            description: "The 23:30 crossing cast off at 23:19 on the night of the storm. Nobody has said who changed the schedule.",
            site: "Harbor Gazette", publishedAt: published, image: duskHarbor(), icon: waveIcon()
        )
        add(
            "https://coastlinereview.org/essays/what-the-tide-keeps", .article,
            title: "What the tide keeps: a year of watching pier 4",
            description: "Fog, freight and a gate that is never quite locked.",
            site: "Coastline Review", author: "Mara Lind", publishedAt: published, image: foggyPier(), icon: dotIcon()
        )
        add(
            "https://vimeo.com/1029384756", .media,
            title: "Pier 4 camera, night of the 3rd (enhanced)",
            site: "Vimeo", duration: 754, image: nightCamera(), icon: playIcon()
        )
        add(
            "https://www.cityarchive.org/maps/harbor-1911", .portrait,
            title: "Survey of the old harbor, 1911",
            description: "Hand-colored map showing the original pier line, the customs house and the channel later filled in.",
            site: "City Archive", image: oldMap(), icon: columnsIcon()
        )
        add(
            "https://x.com/nightwatch_k/status/1842210000000000000", .social,
            title: "Kemi Okafor (@nightwatch_k) on X",
            description: "Was on the night shift at pier 4. The gate was open before the guard got there, and there was a second boat with no lights.",
            site: "X", image: avatar()
        )
        add(
            "https://github.com/harbor-ops/schedules", .compact,
            title: "harbor-ops/schedules",
            description: "Ferry timetables and their change history, published by the port authority.",
            site: "GitHub", icon: ringIcon()
        )
        let unreachable = URL(string: "https://records.harbor-authority.gov/claims/2026-1187")!
        samples.append(Sample(url: unreachable, preview: .fallback(for: unreachable, at: date)))
        samples.append(Sample(url: URL(string: "https://www.harborgazette.com/live")!, preview: nil))
        return samples
    }

    // MARK: Pictures

    private static func draw(_ width: Int, _ height: Int, _ body: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        body(context, CGFloat(width), CGFloat(height))
        return context.makeImage()
    }

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// A vertical gradient; `stops` run from the bottom (0) to the top (1).
    private static func fill(_ context: CGContext, _ rect: CGRect, _ stops: [(CGFloat, UInt32)]) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { color($0.1) } as CFArray,
            locations: stops.map(\.0)
        ) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        context.restoreGState()
    }

    private static func glow(_ context: CGContext, at center: CGPoint, radius: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1]
        ) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    static func duskHarbor() -> CGImage? {
        draw(1200, 630) { c, w, h in
            let horizon = h * 0.4
            fill(c, CGRect(x: 0, y: horizon, width: w, height: h - horizon), [(0, 0xF39A55), (0.25, 0xC7566B), (0.6, 0x4B2E6B), (1, 0x15183A)])
            glow(c, at: CGPoint(x: w * 0.68, y: horizon + 70), radius: 320, 0xFFC27A, 0.55)
            c.setFillColor(color(0xFFE2A8))
            c.fillEllipse(in: CGRect(x: w * 0.68 - 46, y: horizon + 24, width: 92, height: 92))
            fill(c, CGRect(x: 0, y: 0, width: w, height: horizon), [(0, 0x0A1024), (1, 0x2A2C55)])
            // The sun's reflection, broken by the waves.
            for row in 0..<14 {
                let y = horizon - 10 - CGFloat(row) * 17
                let half = 70 - CGFloat(row) * 3.5
                c.setFillColor(color(0xFFB36B, 0.55 - CGFloat(row) * 0.03))
                c.fill(CGRect(x: w * 0.68 - half + CGFloat((row * 37) % 23) - 11, y: y, width: half * 2, height: 4))
            }
            // Pier and lighthouse.
            c.setFillColor(color(0x07091A))
            c.fill(CGRect(x: 0, y: horizon - 6, width: w * 0.46, height: 22))
            for post in 0..<10 {
                c.fill(CGRect(x: CGFloat(post) * w * 0.046 + 12, y: horizon - 60, width: 9, height: 60))
            }
            c.fill(CGRect(x: w * 0.16, y: horizon + 16, width: 30, height: 120))
            c.fill(CGRect(x: w * 0.16 - 8, y: horizon + 136, width: 46, height: 14))
            glow(c, at: CGPoint(x: w * 0.16 + 15, y: horizon + 166), radius: 70, 0xFFF1C4, 0.9)
            // Cranes on the far shore.
            c.setStrokeColor(color(0x1A1838))
            c.setLineWidth(5)
            for crane in 0..<3 {
                let x = w * (0.84 + CGFloat(crane) * 0.05)
                c.strokeLineSegments(between: [
                    CGPoint(x: x, y: horizon), CGPoint(x: x, y: horizon + 90),
                    CGPoint(x: x - 40, y: horizon + 86), CGPoint(x: x + 30, y: horizon + 86),
                ])
            }
        }
    }

    static func foggyPier() -> CGImage? {
        draw(1600, 1000) { c, w, h in
            fill(c, CGRect(x: 0, y: 0, width: w, height: h), [(0, 0x5E7A84), (0.38, 0x9FB3B8), (0.4, 0xC9D2CF), (1, 0xE9E3D6)])
            c.setFillColor(color(0x8A9BA0, 0.55))
            let hills = CGMutablePath()
            hills.move(to: CGPoint(x: 0, y: h * 0.4))
            for step in 0...20 {
                let x = CGFloat(step) * w / 20
                hills.addLine(to: CGPoint(x: x, y: h * (0.46 + 0.05 * sin(CGFloat(step) * 0.9) + 0.03 * sin(CGFloat(step) * 2.3))))
            }
            hills.addLine(to: CGPoint(x: w, y: h * 0.4))
            c.addPath(hills)
            c.fillPath()
            // Posts marching into the fog.
            for post in 0..<11 {
                let t = CGFloat(post) / 10
                let x = w * (0.12 + 0.6 * t)
                let height = h * (0.42 - 0.3 * t)
                let width = 34 - 26 * t
                c.setFillColor(color(0x2C383E, 0.95 - 0.7 * t))
                c.fill(CGRect(x: x, y: h * 0.4 - height * 0.5, width: width, height: height))
            }
            c.setFillColor(color(0x2C383E, 0.85))
            c.fill(CGRect(x: w * 0.1, y: h * 0.55, width: w * 0.66, height: 14))
            glow(c, at: CGPoint(x: w * 0.78, y: h * 0.78), radius: 420, 0xFFF6E0, 0.5)
        }
    }

    static func nightCamera() -> CGImage? {
        draw(1280, 720) { c, w, h in
            fill(c, CGRect(x: 0, y: 0, width: w, height: h), [(0, 0x08140F), (0.5, 0x0F2A20), (1, 0x061009)])
            glow(c, at: CGPoint(x: w * 0.3, y: h * 0.72), radius: 360, 0xB8FFD8, 0.45)
            c.setFillColor(color(0xE8FFF2))
            c.fillEllipse(in: CGRect(x: w * 0.3 - 14, y: h * 0.72 - 14, width: 28, height: 28))
            // Lamp post and the quay edge in perspective.
            c.setFillColor(color(0x020604))
            c.fill(CGRect(x: w * 0.3 - 4, y: h * 0.2, width: 8, height: h * 0.52))
            c.setStrokeColor(color(0x3F7A5F, 0.6))
            c.setLineWidth(2)
            for line in 0..<9 {
                let x = w * CGFloat(line) / 8
                c.strokeLineSegments(between: [CGPoint(x: w * 0.55, y: h * 0.42), CGPoint(x: x * 1.6 - w * 0.3, y: 0)])
            }
            // A boat with no lights.
            c.setFillColor(color(0x010302))
            let hull = CGMutablePath()
            hull.move(to: CGPoint(x: w * 0.62, y: h * 0.4))
            hull.addLine(to: CGPoint(x: w * 0.9, y: h * 0.4))
            hull.addLine(to: CGPoint(x: w * 0.86, y: h * 0.33))
            hull.addLine(to: CGPoint(x: w * 0.65, y: h * 0.33))
            hull.closeSubpath()
            c.addPath(hull)
            c.fillPath()
            c.fill(CGRect(x: w * 0.7, y: h * 0.4, width: w * 0.08, height: h * 0.07))
            // Scan lines.
            c.setFillColor(color(0x000000, 0.18))
            for y in stride(from: 0, to: h, by: 4) { c.fill(CGRect(x: 0, y: y, width: w, height: 1.5)) }
        }
    }

    static func oldMap() -> CGImage? {
        draw(900, 1200) { c, w, h in
            fill(c, CGRect(x: 0, y: 0, width: w, height: h), [(0, 0xC9A86E), (1, 0xEEDDB8)])
            let coast = CGMutablePath()
            coast.move(to: CGPoint(x: 0, y: 0))
            for step in 0...24 {
                let y = CGFloat(step) * h / 24
                coast.addLine(to: CGPoint(x: w * (0.42 + 0.1 * sin(CGFloat(step) * 0.7) + 0.05 * sin(CGFloat(step) * 1.9)), y: y))
            }
            coast.addLine(to: CGPoint(x: 0, y: h))
            coast.closeSubpath()
            c.addPath(coast)
            c.setFillColor(color(0x8FB3AE))
            c.fillPath()
            c.addPath(coast)
            c.setStrokeColor(color(0x5A4122))
            c.setLineWidth(3)
            c.strokePath()
            c.setStrokeColor(color(0x5A4122, 0.22))
            c.setLineWidth(1.5)
            for line in 1..<8 {
                c.strokeLineSegments(between: [CGPoint(x: w * CGFloat(line) / 8, y: 0), CGPoint(x: w * CGFloat(line) / 8, y: h)])
                c.strokeLineSegments(between: [CGPoint(x: 0, y: h * CGFloat(line) / 8), CGPoint(x: w, y: h * CGFloat(line) / 8)])
            }
            // Piers.
            c.setFillColor(color(0x5A4122))
            for pier in 0..<4 {
                c.fill(CGRect(x: w * 0.3, y: h * (0.25 + 0.14 * CGFloat(pier)), width: w * 0.2, height: 12))
            }
            // The route in red.
            c.setStrokeColor(color(0xB0302A))
            c.setLineWidth(5)
            c.setLineDash(phase: 0, lengths: [16, 10])
            c.move(to: CGPoint(x: w * 0.1, y: h * 0.12))
            c.addCurve(to: CGPoint(x: w * 0.4, y: h * 0.67), control1: CGPoint(x: w * 0.3, y: h * 0.3), control2: CGPoint(x: w * 0.05, y: h * 0.55))
            c.strokePath()
            c.setLineDash(phase: 0, lengths: [])
            // Compass.
            c.setStrokeColor(color(0x5A4122))
            c.setLineWidth(3)
            c.strokeEllipse(in: CGRect(x: w * 0.68, y: h * 0.78, width: 160, height: 160))
            c.strokeLineSegments(between: [
                CGPoint(x: w * 0.68 + 80, y: h * 0.78 - 20), CGPoint(x: w * 0.68 + 80, y: h * 0.78 + 180),
                CGPoint(x: w * 0.68 - 20, y: h * 0.78 + 80), CGPoint(x: w * 0.68 + 180, y: h * 0.78 + 80),
            ])
        }
    }

    static func avatar() -> CGImage? {
        draw(400, 400) { c, w, h in
            fill(c, CGRect(x: 0, y: 0, width: w, height: h), [(0, 0xC2405A), (1, 0xF4A259)])
            c.setFillColor(color(0x2A1714))
            c.fillEllipse(in: CGRect(x: w * 0.32, y: h * 0.42, width: w * 0.36, height: w * 0.4))
            c.fillEllipse(in: CGRect(x: w * 0.12, y: -h * 0.3, width: w * 0.76, height: h * 0.7))
        }
    }

    // MARK: Icons

    private static func icon(_ background: UInt32, _ body: (CGContext, CGFloat) -> Void) -> CGImage? {
        draw(128, 128) { c, w, _ in
            c.setFillColor(color(background))
            c.fill(CGRect(x: 0, y: 0, width: w, height: w))
            body(c, w)
        }
    }

    static func waveIcon() -> CGImage? {
        icon(0x13254A) { c, w in
            c.setStrokeColor(color(0xFFFFFF))
            c.setLineWidth(10)
            c.setLineCap(.round)
            for row in 0..<2 {
                let y = w * (0.42 + 0.2 * CGFloat(row))
                c.move(to: CGPoint(x: w * 0.18, y: y))
                c.addCurve(to: CGPoint(x: w * 0.82, y: y), control1: CGPoint(x: w * 0.4, y: y + 22), control2: CGPoint(x: w * 0.6, y: y - 22))
            }
            c.strokePath()
        }
    }

    static func dotIcon() -> CGImage? {
        icon(0xF1E9DA) { c, w in
            c.setFillColor(color(0x24323A))
            c.fillEllipse(in: CGRect(x: w * 0.25, y: w * 0.25, width: w * 0.5, height: w * 0.5))
        }
    }

    static func playIcon() -> CGImage? {
        icon(0x19B7EA) { c, w in
            c.setFillColor(color(0xFFFFFF))
            c.addPath(WebCardArt.playTriangle(in: CGRect(x: 0, y: 0, width: w * 1.3, height: w).offsetBy(dx: -w * 0.15, dy: 0)))
            c.fillPath()
        }
    }

    static func columnsIcon() -> CGImage? {
        icon(0x6B4A2B) { c, w in
            c.setFillColor(color(0xF4E6C8))
            c.fill(CGRect(x: w * 0.2, y: w * 0.2, width: w * 0.6, height: w * 0.08))
            c.fill(CGRect(x: w * 0.2, y: w * 0.68, width: w * 0.6, height: w * 0.1))
            for column in 0..<3 {
                c.fill(CGRect(x: w * (0.26 + 0.18 * CGFloat(column)), y: w * 0.3, width: w * 0.1, height: w * 0.36))
            }
        }
    }

    static func ringIcon() -> CGImage? {
        icon(0x161B22) { c, w in
            c.setStrokeColor(color(0xF0F6FC))
            c.setLineWidth(12)
            c.strokeEllipse(in: CGRect(x: w * 0.24, y: w * 0.24, width: w * 0.52, height: w * 0.52))
        }
    }
}
#endif
