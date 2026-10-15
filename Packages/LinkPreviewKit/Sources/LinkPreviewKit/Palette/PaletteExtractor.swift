import Foundation
import BoardKit

/// A color in OKLab: perceptual lightness `l` (0…1) and two opponent axes.
public struct OKLab: Sendable, Equatable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    public var chroma: Double { (a * a + b * b).squareRoot() }

    /// From 8-bit sRGB.
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), bl = linear(blue)
        let lms = (
            cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl),
            cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl),
            cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        )
        l = 0.2104542553 * lms.0 + 0.7936177850 * lms.1 - 0.0040720468 * lms.2
        a = 1.9779984951 * lms.0 - 2.4285922050 * lms.1 + 0.4505937099 * lms.2
        b = 0.0259040371 * lms.0 + 0.7827717662 * lms.1 - 0.8086757660 * lms.2
    }

    /// `#RRGGBB`, clipped into sRGB.
    public var hex: String {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let (lc, mc, sc) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_)
        let linear = [
            4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
            -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
            -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc,
        ]
        let bytes = linear.map { value -> Int in
            let clamped = min(max(value, 0), 1)
            let encoded = clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
            return Int((encoded * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }

    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: UInt8((value >> 16) & 0xFF), green: UInt8((value >> 8) & 0xFF), blue: UInt8(value & 0xFF))
    }

    func distanceSquared(to other: OKLab) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return dl * dl + da * da + db * db
    }

    /// Same hue, new lightness, chroma scaled.
    func with(lightness: Double, chromaScale: Double = 1) -> OKLab {
        OKLab(l: lightness, a: a * chromaScale, b: b * chromaScale)
    }
}

/// Five role-based swatches from an image's pixels (DESIGN.md §7.4).
public enum PaletteExtractor {
    /// Clusters `pixels` (8-bit RGBA, any order) and assigns the five roles. Pixels that are
    /// mostly transparent are skipped. Deterministic for the same input.
    public static func palette(rgba pixels: [UInt8]) -> LinkPalette? {
        var colors: [OKLab] = []
        colors.reserveCapacity(pixels.count / 4)
        var index = 0
        while index + 3 < pixels.count {
            if pixels[index + 3] >= 128 {
                colors.append(OKLab(red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2]))
            }
            index += 4
        }
        return palette(colors: colors)
    }

    public static func palette(colors: [OKLab]) -> LinkPalette? {
        guard !colors.isEmpty else { return nil }
        let clusters = kMeans(colors, k: min(8, colors.count), iterations: 6)
        return assignRoles(clusters, total: colors.count)
    }

    /// A palette built around one color, for pages with a `theme-color` but no image.
    public static func palette(around hex: String) -> LinkPalette? {
        guard let base = OKLab(hex: hex) else { return nil }
        return palette(around: base)
    }

    /// A palette from a hash of the domain, for previews that couldn't be fetched.
    public static func palette(forDomain domain: String) -> LinkPalette {
        // FNV-1a, so the same domain always gets the same colors.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in domain.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hue = Double(hash % 360) * .pi / 180
        return palette(around: OKLab(l: 0.6, a: 0.12 * cos(hue), b: 0.12 * sin(hue)))
    }

    static func palette(around base: OKLab) -> LinkPalette {
        let chroma = max(base.chroma, 0.04)
        let scale = chroma / max(base.chroma, 0.0001)
        let tinted = base.chroma < 0.0001 ? OKLab(l: base.l, a: 0.02, b: -0.03) : OKLab(l: base.l, a: base.a * scale, b: base.b * scale)
        return LinkPalette(
            vibrant: tinted.with(lightness: 0.62, chromaScale: 1.2).hex,
            muted: tinted.with(lightness: 0.52, chromaScale: 0.45).hex,
            darkVibrant: tinted.with(lightness: 0.34, chromaScale: 0.9).hex,
            darkMuted: tinted.with(lightness: 0.24, chromaScale: 0.4).hex,
            light: tinted.with(lightness: 0.93, chromaScale: 0.25).hex
        )
    }

    struct Cluster {
        var center: OKLab
        var population: Int
    }

    /// k-means with k-means++ seeding from a fixed-seed generator.
    static func kMeans(_ colors: [OKLab], k: Int, iterations: Int) -> [Cluster] {
        var random = SplitMix(seed: UInt64(colors.count) &* 0x9E37_79B9)
        var centers = [colors[Int(random.next() % UInt64(colors.count))]]
        var nearest = colors.map { $0.distanceSquared(to: centers[0]) }
        while centers.count < k {
            let total = nearest.reduce(0, +)
            guard total > 0 else { break }
            var pick = Double(random.next() % 1_000_000) / 1_000_000 * total
            var chosen = colors.count - 1
            for (index, distance) in nearest.enumerated() {
                pick -= distance
                if pick <= 0 {
                    chosen = index
                    break
                }
            }
            centers.append(colors[chosen])
            for (index, color) in colors.enumerated() {
                nearest[index] = min(nearest[index], color.distanceSquared(to: colors[chosen]))
            }
        }

        var assignment = [Int](repeating: 0, count: colors.count)
        for _ in 0..<iterations {
            for (index, color) in colors.enumerated() {
                var best = 0
                var bestDistance = Double.infinity
                for (c, center) in centers.enumerated() {
                    let distance = color.distanceSquared(to: center)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = c
                    }
                }
                assignment[index] = best
            }
            var sums = [(l: Double, a: Double, b: Double, n: Int)](repeating: (0, 0, 0, 0), count: centers.count)
            for (index, color) in colors.enumerated() {
                let c = assignment[index]
                sums[c].l += color.l
                sums[c].a += color.a
                sums[c].b += color.b
                sums[c].n += 1
            }
            for c in centers.indices where sums[c].n > 0 {
                let n = Double(sums[c].n)
                centers[c] = OKLab(l: sums[c].l / n, a: sums[c].a / n, b: sums[c].b / n)
            }
        }
        var populations = [Int](repeating: 0, count: centers.count)
        for c in assignment { populations[c] += 1 }
        return zip(centers, populations).map { Cluster(center: $0, population: $1) }.filter { $0.population > 0 }
    }

    /// Scores clusters into roles by population, chroma and lightness, then fills any role
    /// nobody won by shifting the nearest swatch's lightness.
    static func assignRoles(_ clusters: [Cluster], total: Int) -> LinkPalette? {
        guard !clusters.isEmpty else { return nil }
        func share(_ cluster: Cluster) -> Double { Double(cluster.population) / Double(max(total, 1)) }
        func pick(_ lightness: ClosedRange<Double>, vivid: Bool) -> OKLab? {
            clusters
                .filter { lightness.contains($0.center.l) && (vivid ? $0.center.chroma >= 0.06 : $0.center.chroma < 0.09) }
                .max { score($0, vivid: vivid) < score($1, vivid: vivid) }?
                .center
        }
        func score(_ cluster: Cluster, vivid: Bool) -> Double {
            vivid ? cluster.center.chroma * share(cluster).squareRoot() : share(cluster)
        }
        let dominant = clusters.max { $0.population < $1.population }!.center
        let mostVivid = clusters.max { $0.center.chroma * share($0).squareRoot() < $1.center.chroma * share($1).squareRoot() }!.center

        let vibrant = pick(0.45...0.80, vivid: true) ?? mostVivid.with(lightness: min(max(mostVivid.l, 0.55), 0.7), chromaScale: 1.15)
        let muted = pick(0.35...0.65, vivid: false) ?? dominant.with(lightness: 0.5, chromaScale: 0.45)
        let darkVibrant = pick(0...0.40, vivid: true) ?? vibrant.with(lightness: 0.32, chromaScale: 0.9)
        let darkMuted = pick(0...0.35, vivid: false) ?? dominant.with(lightness: 0.22, chromaScale: 0.4)
        let light = clusters.filter { $0.center.l > 0.80 }.max { share($0) < share($1) }?.center
            ?? dominant.with(lightness: 0.93, chromaScale: 0.25)
        return LinkPalette(vibrant: vibrant.hex, muted: muted.hex, darkVibrant: darkVibrant.hex, darkMuted: darkMuted.hex, light: light.hex)
    }
}

/// A tiny deterministic random generator.
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
}
