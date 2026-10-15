import QuartzCore

/// Cork grain behind a Cork board.
///
/// One seamless tile is drawn procedurally when the theme is applied and repeated by
/// replicator layers. It moves with the board when you pan but keeps its size when you
/// zoom, like the grain of the cork itself rather than a picture of it, so it never
/// pixelates.
@MainActor
final class GrainTexture {
    nonisolated static let tileSize: CGFloat = 256

    let layer = CALayer()
    private let rows = CAReplicatorLayer()
    private let columns = CAReplicatorLayer()
    private let tile = CALayer()
    private var drawn: (color: RGBA, scale: CGFloat)?

    init() {
        layer.masksToBounds = true
        layer.addSublayer(rows)
        rows.addSublayer(columns)
        columns.addSublayer(tile)
    }

    /// Draws the tile in `color` (the dark specks; light ones are added) at `scale`.
    func setColor(_ color: RGBA, scale: CGFloat) {
        guard drawn?.color != color || drawn?.scale != scale else { return }
        drawn = (color, scale)
        tile.contents = Self.makeTile(color: color, scale: scale)
        tile.contentsScale = scale
    }

    func update(camera: Camera, viewSize size: CGSize) {
        let frame = CGRect(origin: .zero, size: size)
        layer.frame = frame
        rows.frame = frame
        columns.frame = frame
        guard size.width > 0, size.height > 0 else { return }
        let side = Self.tileSize
        let origin = camera.worldToView(.zero, in: size)
        func start(_ value: CGFloat) -> CGFloat {
            let remainder = value.truncatingRemainder(dividingBy: side)
            return (remainder < 0 ? remainder + side : remainder) - side
        }
        let first = CGPoint(x: start(origin.x), y: start(origin.y))
        tile.frame = CGRect(origin: first, size: CGSize(width: side, height: side))
        columns.instanceCount = Int((size.width - first.x) / side) + 1
        columns.instanceTransform = CATransform3DMakeTranslation(side, 0, 0)
        rows.instanceCount = Int((size.height - first.y) / side) + 1
        rows.instanceTransform = CATransform3DMakeTranslation(0, side, 0)
    }

    /// Soft blotches, dark granules and a few light ones, wrapped at the edges so the tile
    /// repeats without seams. Seeded, so it's the same every time.
    nonisolated static func makeTile(color: RGBA, scale: CGFloat) -> CGImage? {
        let side = tileSize
        let pixels = Int((side * scale).rounded())
        guard pixels > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        var random = SplitMix(seed: 0xC0_4C)

        func speck(radius: ClosedRange<Double>, alpha: ClosedRange<Double>, tone: RGBA, stretch: Bool) {
            let r = CGFloat(random.next(in: radius))
            let w = stretch ? r * CGFloat(random.next(in: 1...2.2)) : r
            let center = CGPoint(x: CGFloat(random.next(in: 0...Double(side))), y: CGFloat(random.next(in: 0...Double(side))))
            context.setFillColor(tone.opacity(random.next(in: alpha)).cgColor)
            for dx in [-side, 0, side] {
                for dy in [-side, 0, side] {
                    let rect = CGRect(x: center.x + dx - w, y: center.y + dy - r, width: w * 2, height: r * 2)
                    guard rect.intersects(CGRect(x: 0, y: 0, width: side, height: side)) else { continue }
                    context.fillEllipse(in: rect)
                }
            }
        }

        let ink = color.opacity(1)
        let strength = color.alpha
        for _ in 0..<220 { speck(radius: 5...16, alpha: 0.05 * strength...0.12 * strength, tone: ink, stretch: true) }
        for _ in 0..<1600 { speck(radius: 0.5...2.2, alpha: 0.25 * strength...0.7 * strength, tone: ink, stretch: true) }
        for _ in 0..<520 { speck(radius: 0.5...1.6, alpha: 0.06...0.16, tone: RGBA(0xFFE9C9), stretch: false) }
        return context.makeImage()
    }
}

/// A small seeded random generator, so generated textures are stable.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}
