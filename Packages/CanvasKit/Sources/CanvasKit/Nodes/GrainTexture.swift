import Foundation
import QuartzCore

/// Cork grain behind a Cork board.
///
/// One seamless tile is drawn procedurally when the theme is applied and repeated by
/// replicator layers. The grain is glued to the board, like the cork itself: it pans and
/// zooms with the cards and never slides under them. So it doesn't grow blotchy as you zoom
/// in (or turn to dust as you zoom out), it's shown at two neighbouring sizes, a power of two
/// apart, and the finer one fades in as the coarser one grows. On screen a tile is always
/// between 128 and 512 points wide.
@MainActor
final class GrainTexture {
    nonisolated static let tileSize: CGFloat = 256

    let layer = CALayer()
    private let coarse = TileSet()
    private let fine = TileSet()
    private var drawn: (color: RGBA, scale: CGFloat)?

    init() {
        layer.masksToBounds = true
        layer.addSublayer(coarse.layer)
        layer.addSublayer(fine.layer)
    }

    /// Draws the tile in `color` (the dark specks; light ones are added) for a screen of
    /// `scale` pixels per point.
    func setColor(_ color: RGBA, scale: CGFloat) {
        guard drawn?.color != color || drawn?.scale != scale else { return }
        drawn = (color, scale)
        // Twice the screen's detail: a tile is shown at up to twice its nominal size.
        let image = Self.makeTile(color: color, scale: scale * 2)
        coarse.setImage(image)
        fine.setImage(image)
    }

    func update(camera: Camera, viewSize size: CGSize) {
        layer.frame = CGRect(origin: .zero, size: size)
        guard size.width > 0, size.height > 0 else { return }
        let octave = Self.octave(forZoom: camera.zoom)
        // Tiles start at the board's origin, so the pattern stays put on the board.
        let origin = camera.worldToView(.zero, in: size)
        coarse.update(origin: origin, side: octave.coarseSide, size: size)
        fine.update(origin: origin, side: octave.coarseSide / 2, size: size)
        coarse.layer.opacity = Float(1 - octave.fineOpacity)
        fine.layer.opacity = Float(octave.fineOpacity)
    }

    /// The coarse tile's size on screen at `zoom`, from one to two nominal tiles, and how far
    /// the fine tiles (half that size) have faded in. Both cover a power-of-two fraction of
    /// 256 board points, so at an exact power-of-two zoom the fine tiles have fully taken
    /// over and become the next coarse ones: nothing jumps.
    nonisolated static func octave(forZoom zoom: CGFloat) -> (coarseSide: CGFloat, fineOpacity: CGFloat) {
        let level = log2(Double(max(zoom, 0.0001)))
        let fraction = level - level.rounded(.down)
        let t = min(max((fraction - 0.25) / 0.75, 0), 1)
        return (tileSize * CGFloat(exp2(fraction)), CGFloat(t * t * (3 - 2 * t)))
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

/// One size of grain: a tile repeated across and down from the board's origin.
@MainActor
private final class TileSet {
    let layer = CAReplicatorLayer()
    private let columns = CAReplicatorLayer()
    private let tile = CALayer()

    init() {
        layer.addSublayer(columns)
        columns.addSublayer(tile)
        // Mipmapped, so tiles shown small don't shimmer.
        tile.minificationFilter = .trilinear
    }

    func setImage(_ image: CGImage?) {
        tile.contents = image
    }

    func update(origin: CGPoint, side: CGFloat, size: CGSize) {
        let frame = CGRect(origin: .zero, size: size)
        layer.frame = frame
        columns.frame = frame
        func start(_ value: CGFloat) -> CGFloat {
            let remainder = value.truncatingRemainder(dividingBy: side)
            return (remainder < 0 ? remainder + side : remainder) - side
        }
        let first = CGPoint(x: start(origin.x), y: start(origin.y))
        tile.frame = CGRect(origin: first, size: CGSize(width: side, height: side))
        columns.instanceCount = Int((size.width - first.x) / side) + 1
        columns.instanceTransform = CATransform3DMakeTranslation(side, 0, 0)
        layer.instanceCount = Int((size.height - first.y) / side) + 1
        layer.instanceTransform = CATransform3DMakeTranslation(0, side, 0)
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
