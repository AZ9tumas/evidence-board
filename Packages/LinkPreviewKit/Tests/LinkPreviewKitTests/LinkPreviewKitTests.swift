import Foundation
import Testing
import BoardKit
@testable import LinkPreviewKit

@Suite("Link URLs")
struct LinkURLTests {
    @Test func acceptsWebAddressesOnly() {
        #expect(LinkURL.webURL(from: " https://Example.com/a?b=1#frag ")?.absoluteString == "https://example.com/a?b=1")
        #expect(LinkURL.webURL(from: "example.com/story")?.absoluteString == "https://example.com/story")
        #expect(LinkURL.webURL(from: "www.theverge.com")?.absoluteString == "https://www.theverge.com/")
        #expect(LinkURL.webURL(from: "javascript:alert(1)") == nil)
        #expect(LinkURL.webURL(from: "file:///etc/passwd") == nil)
        #expect(LinkURL.webURL(from: "ftp://example.com/x") == nil)
        #expect(LinkURL.webURL(from: "two words.com") == nil)
        #expect(LinkURL.webURL(from: "not a url") == nil)
        #expect(LinkURL.webURL(from: "readme.md") == nil)
        #expect(LinkURL.webURL(from: "readme.md/raw")?.host == "readme.md")
        #expect(LinkURL.webURL(from: "") == nil)
    }

    @Test func stripsTrackingAndDefaults() {
        let url = URL(string: "HTTPS://News.Example.com:443/a?id=7&utm_source=x&fbclid=y&si=z#top")
        #expect(LinkURL.normalize(url)?.absoluteString == "https://news.example.com/a?id=7")
        #expect(LinkURL.normalize(url, stripTracking: false)?.absoluteString.contains("utm_source") == true)
        #expect(LinkURL.normalize(URL(string: "http://example.com:80"))?.absoluteString == "http://example.com/")
        #expect(LinkURL.displayHost(of: URL(string: "https://www.theverge.com/x")!) == "theverge.com")
    }
}

@Suite("Head parser")
struct HeadParserTests {
    let base = URL(string: "https://example.com/dir/page.html")!

    @Test func readsMetaLinksAndTitle() throws {
        let html = """
        <html><head><title> Hello &amp; welcome </title>
        <meta property="og:title" content="OG &quot;title&quot;">
        <meta name='description' content='Plain description'>
        <meta itemprop=duration content=PT1M>
        <link rel="icon" sizes="32x32" href="icon.png">
        <link rel="apple-touch-icon" href="/touch.png">
        </head><body><meta property="og:title" content="late"></body></html>
        """
        let head = HTMLHeadParser.parse(html, baseURL: base)
        #expect(head.title == "Hello & welcome")
        #expect(head.first("og:title") == "OG \"title\"")
        #expect(head.first("description") == "Plain description")
        #expect(head.first("duration") == "PT1M")
        #expect(head.meta["og:title"]?.count == 1)
        #expect(head.links.map(\.href.absoluteString) == ["https://example.com/dir/icon.png", "https://example.com/touch.png"])
    }

    @Test func groupsOpenGraphImagesWithTheirSizes() {
        let html = """
        <meta property="og:image" content="/a.jpg"><meta property="og:image:width" content="300">
        <meta property="og:image" content="/b.jpg"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
        """
        let images = HTMLHeadParser.parse(html, baseURL: base).openGraphImages
        #expect(images.map(\.url.lastPathComponent) == ["a.jpg", "b.jpg"])
        #expect(images[0].width == 300 && images[0].height == nil)
        #expect(images[1].width == 1200 && images[1].height == 630)
    }

    @Test func survivesTruncationAndJunk() {
        let html = "<head><title>Cut off</title><meta property=\"og:description\" content=\"never fini"
        let head = HTMLHeadParser.parse(html, baseURL: base)
        #expect(head.title == "Cut off")
        #expect(HTMLHeadParser.parse("<<<>>> <!-- <title>x", baseURL: base).title == nil)
        #expect(HTMLHeadParser.parse(String(repeating: "<a ", count: 10_000), baseURL: base).title == nil)
    }

    @Test func decodesEntities() {
        #expect(HTMLText.clean("A&nbsp;&amp;&#32;B &#x1F6A2; &unknown; &lt;3") == "A & B 🚢 &unknown; <3")
    }

    @Test func readsJSONLDGraphs() {
        let html = """
        <script type="application/ld+json">{"@graph":[{"@type":"WebSite","name":"Site"},
        {"@type":["NewsArticle"],"headline":"Story","author":[{"name":"A"},{"name":"B"},{"name":"C"}],
        "datePublished":"2026-10-01T10:00:00Z","image":{"url":"https://example.com/i.jpg"}}]}</script>
        <script type="application/ld+json">{ broken json</script>
        """
        let items = HTMLHeadParser.parse(html, baseURL: base).jsonLD
        let article = try? #require(items.first { $0.isArticle })
        #expect(article?.headline == "Story")
        #expect(article?.author == "A, B")
        #expect(article?.images.first?.absoluteString == "https://example.com/i.jpg")
        #expect(article?.datePublished == Date(timeIntervalSince1970: 1_790_848_800))
    }

    @Test func parsesDurationsAndDates() {
        #expect(ISODuration.seconds("PT4M13S") == 253)
        #expect(ISODuration.seconds("PT1H") == 3600)
        #expect(ISODuration.seconds("P1DT1S") == 86_401)
        #expect(ISODuration.seconds("PT") == nil)
        #expect(ISODuration.seconds("90") == 90)
        #expect(ISODate.parse("2026-10-01") != nil)
        #expect(ISODate.parse("2026-10-01T10:00:00.123+02:00") != nil)
        #expect(ISODate.parse("yesterday") == nil)
        #expect(ColorText.hex("#abc") == "#AABBCC")
        #expect(ColorText.hex("rgb(255, 0, 10)") == "#FF000A")
        #expect(ColorText.hex("red") == nil)
    }
}

@Suite("Palette")
struct PaletteTests {
    /// A synthetic image: mostly dark navy, a band of vivid orange, a little near-white.
    static func pixels() -> [UInt8] {
        var bytes: [UInt8] = []
        for index in 0..<(64 * 64) {
            let (r, g, b): (UInt8, UInt8, UInt8) = switch index % 10 {
            case 0...5: (18, 24, 48)
            case 6...8: (240, 120, 30)
            default: (240, 240, 235)
            }
            bytes += [r, g, b, 255]
        }
        return bytes
    }

    @Test func rolesLandInTheirLightnessBands() throws {
        let palette = try #require(PaletteExtractor.palette(rgba: Self.pixels()))
        let vibrant = try #require(OKLab(hex: palette.vibrant))
        let darkMuted = try #require(OKLab(hex: palette.darkMuted))
        let light = try #require(OKLab(hex: palette.light))
        #expect(vibrant.chroma > 0.1)
        #expect(darkMuted.l < 0.4)
        #expect(light.l > 0.8)
        // Same input, same palette.
        #expect(PaletteExtractor.palette(rgba: Self.pixels()) == palette)
    }

    @Test func ignoresTransparentPixels() {
        let clear = [UInt8](repeating: 0, count: 64 * 4)
        #expect(PaletteExtractor.palette(rgba: clear) == nil)
    }

    @Test func roundTripsHex() throws {
        for hex in ["#FF3B4E", "#12306E", "#E8EEFF", "#000000", "#FFFFFF"] {
            #expect(try #require(OKLab(hex: hex)).hex == hex)
        }
    }

    @Test func domainPalettesAreStableAndDistinct() {
        #expect(PaletteExtractor.palette(forDomain: "example.com") == PaletteExtractor.palette(forDomain: "EXAMPLE.com"))
        #expect(PaletteExtractor.palette(forDomain: "example.com") != PaletteExtractor.palette(forDomain: "example.org"))
        let themed = PaletteExtractor.palette(around: "#7A3DF0")
        #expect(themed != nil)
    }
}

@Suite("Variants and merging")
struct VariantTests {
    @Test func followsTheDesignTable() {
        #expect(VariantRules.variant(for: .page, image: PixelSize(width: 1200, height: 630)) == .hero)
        #expect(VariantRules.variant(for: .article, image: PixelSize(width: 1200, height: 630)) == .article)
        #expect(VariantRules.variant(for: .page, image: PixelSize(width: 600, height: 900)) == .portrait)
        #expect(VariantRules.variant(for: .video, image: PixelSize(width: 1280, height: 720)) == .media)
        #expect(VariantRules.variant(for: .video, image: nil) == .compact)
        #expect(VariantRules.variant(for: .social, image: nil) == .social)
        #expect(VariantRules.variant(for: .page, image: nil) == .compact)
        #expect(VariantRules.variant(for: .page, image: PixelSize(width: 120, height: 120)) == .compact)
        #expect(VariantRules.variant(for: .page, image: PixelSize(width: 3000, height: 600)) == .compact)
    }

    @Test func previewFallsBackSensibly() {
        let url = URL(string: "https://unreachable.example.com/x")!
        let fallback = LinkPreview.fallback(for: url)
        #expect(fallback.variant == .fallback)
        #expect(fallback.title == "unreachable.example.com")

        var page = PageInfo(url: url)
        page.themeColor = "#336699"
        let preview = LinkPreview.make(from: page, image: Data([1, 2, 3]), imageSize: nil, icon: nil, palette: nil)
        #expect(preview.variant == .compact)
        #expect(preview.image == nil) // no size means it didn't decode
        #expect(preview.palette == PaletteExtractor.palette(around: "#336699"))
    }
}

@Suite("Preview cache")
struct PreviewCacheTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lpk-\(UUID().uuidString)")
    }

    @Test func storesAndExpires() async throws {
        let cache = LinkPreviewCache(directory: temporaryDirectory(), maxAge: 100)
        let url = URL(string: "https://example.com/a")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var preview = LinkPreview.fallback(for: url, at: now)
        preview.variant = .hero
        preview.image = Data([1, 2, 3])
        preview.imageSize = PixelSize(width: 1200, height: 630)
        await cache.store(preview)

        let loaded = try #require(await cache.load(url, now: now.addingTimeInterval(10)))
        #expect(loaded == preview)
        #expect(await cache.load(url, now: now.addingTimeInterval(1000)) == nil)
        #expect(await cache.load(URL(string: "https://example.com/b")!, now: now) == nil)
    }

    @Test func prunesOldestPastTheCap() async throws {
        let directory = temporaryDirectory()
        let cache = LinkPreviewCache(directory: directory, maxBytes: 3000)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<4 {
            var preview = LinkPreview.fallback(for: URL(string: "https://example.com/\(index)")!, at: start)
            preview.image = Data(repeating: UInt8(index), count: 1000)
            preview.imageSize = PixelSize(width: 10, height: 10)
            await cache.store(preview)
        }
        await cache.prune()
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".image") }
        #expect(remaining.count < 4)
        #expect(remaining.count >= 1)
    }
}

@Suite("Fetch limiter")
struct FetchLimiterTests {
    @Test func oneAtATimePerHost() async {
        let limiter = FetchLimiter(total: 4)
        let log = Log()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<3 {
                group.addTask {
                    await limiter.acquire(host: "same.example")
                    await log.enter()
                    try? await Task.sleep(for: .milliseconds(20))
                    await log.leave()
                    await limiter.release(host: "same.example")
                    _ = index
                }
            }
        }
        #expect(await log.peak == 1)
    }

    @Test func differentHostsRunTogether() async {
        let limiter = FetchLimiter(total: 2)
        let log = Log()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<4 {
                group.addTask {
                    let host = "host\(index).example"
                    await limiter.acquire(host: host)
                    await log.enter()
                    try? await Task.sleep(for: .milliseconds(30))
                    await log.leave()
                    await limiter.release(host: host)
                }
            }
        }
        #expect(await log.peak == 2)
    }

    actor Log {
        var current = 0
        var peak = 0

        func enter() {
            current += 1
            peak = max(peak, current)
        }

        func leave() {
            current -= 1
        }
    }
}
