import AppKit
import Foundation
import Testing
import BoardKit
import LinkPreviewKit
@testable import CanvasKit

/// A page head from LinkPreviewKit's fixture suite, taken through the pipeline as far as a
/// web card's content, with stand-in assets of the sizes the page's images download as.
struct WebFixture: CustomTestStringConvertible, Sendable {
    let name: String
    let payload: WebPayload
    let assets: [AssetID: Asset]

    var testDescription: String { name }

    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent() // CanvasKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // CanvasKit
        .deletingLastPathComponent() // Packages
        .appending(path: "LinkPreviewKit/Tests/Fixtures/sites")

    static func all() throws -> [WebFixture] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "html" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map(load)
    }

    static func load(_ file: URL) throws -> WebFixture {
        let html = try String(contentsOf: file, encoding: .utf8)
        let name = file.deletingPathExtension().lastPathComponent
        guard let open = html.range(of: "<!-- "), let close = html.range(of: " -->"),
              let json = try JSONSerialization.jsonObject(with: Data(html[open.upperBound..<close.lowerBound].utf8)) as? [String: Any],
              let address = json["url"] as? String, let url = URL(string: address) else {
            throw FixtureError.unreadable(name)
        }
        var imageSize: PixelSize?
        if let size = json["image"] as? [Double], size.count == 2 {
            imageSize = PixelSize(width: Int(size[0]), height: Int(size[1]))
        }
        let page = MetadataMerger.merge(HTMLHeadParser.parse(html, baseURL: url), url: url)
        let preview = LinkPreview.make(from: page, image: nil, imageSize: imageSize, icon: nil, palette: nil)

        var assets: [AssetID: Asset] = [:]
        if let imageSize {
            assets["image-\(name)"] = Asset(mime: "image/jpeg", pixelWidth: imageSize.width, pixelHeight: imageSize.height, data: Data([0]))
        }
        let hasIcon = !page.icons.isEmpty
        if hasIcon {
            assets["icon-\(name)"] = Asset(mime: "image/png", pixelWidth: 64, pixelHeight: 64, data: Data([0]))
        }
        let snapshot = LinkSnapshot(
            fetchedAt: preview.fetchedAt, variant: preview.variant, title: preview.title,
            pageDescription: preview.pageDescription, siteName: preview.siteName, author: preview.author,
            publishedAt: preview.publishedAt, mediaDuration: preview.duration,
            image: imageSize == nil ? nil : "image-\(name)", icon: hasIcon ? "icon-\(name)" : nil,
            palette: preview.palette
        )
        return WebFixture(name: name, payload: WebPayload(url: url, snapshot: snapshot), assets: assets)
    }

    enum FixtureError: Error {
        case unreadable(String)
    }
}

@MainActor
@Suite("Web cards")
struct WebCardTests {
    static let widths: [CGFloat] = [240, 360, 480, 640]
    static var appearance: CanvasAppearance { TextCardTests.appearance }

    @Test func fixturesAreThere() throws {
        #expect(try WebFixture.all().count >= 60)
    }

    /// The exit check of M4: every fixture lays out cleanly at every width.
    @Test(arguments: try WebFixture.all())
    func fixtureLaysOutCleanly(_ fixture: WebFixture) {
        let content = WebCardContent(payload: fixture.payload, assets: fixture.assets, isLoading: false)
        for width in Self.widths {
            let layout = WebCardLayout(content: content, width: width, appearance: Self.appearance)
            Self.checkInvariants(layout, content: content, width: width, name: "\(fixture.name) @\(Int(width))")
        }
    }

    @Test func loadingAndFallbackLayOutCleanly() {
        let url = URL(string: "https://unreachable.example.net/some/long/path?with=query")!
        let loading = WebCardContent(payload: WebPayload(url: url), assets: [:], isLoading: true)
        let unavailable = WebCardContent(payload: WebPayload(url: url), assets: [:], isLoading: false)
        #expect(loading.isLoading && unavailable.variant == .fallback)
        for width in Self.widths {
            let skeleton = WebCardLayout(content: loading, width: width, appearance: Self.appearance)
            #expect(skeleton.blocks.isEmpty && skeleton.skeletonBars.count == 7)
            for bar in skeleton.skeletonBars {
                #expect(CGRect(origin: .zero, size: skeleton.size).contains(bar))
            }
            Self.checkInvariants(
                WebCardLayout(content: unavailable, width: width, appearance: Self.appearance),
                content: unavailable, width: width, name: "fallback @\(Int(width))"
            )
        }
    }

    @Test func variantsUseTheirShapes() throws {
        let fixtures = try WebFixture.all()
        var seen: Set<LinkVariant> = []
        for fixture in fixtures {
            let content = WebCardContent(payload: fixture.payload, assets: fixture.assets, isLoading: false)
            let layout = WebCardLayout(content: content, width: 360, appearance: Self.appearance)
            seen.insert(content.variant)
            switch content.variant {
            case .hero, .article, .media:
                let image = try #require(layout.image)
                #expect(image.minY == WebCardLayout.heroInset && abs(image.width / image.height - 16.0 / 9.0) < 0.02)
                #expect(layout.blocks.allSatisfy { $0.frame.minY >= image.maxY || image.contains($0.frame) })
                #expect((layout.playButton != nil) == (content.variant == .media))
            case .portrait:
                let image = try #require(layout.image)
                #expect(layout.blocks.allSatisfy { $0.frame.minX >= image.maxX })
            case .social:
                #expect(layout.iconIsRound)
                #expect(layout.image == nil || content.imageIsAvatar == false)
            case .compact, .fallback:
                #expect(layout.fullMesh && layout.image == nil)
            }
        }
        // The suite covers every layout but fallback, which is tested above.
        #expect(seen.isSuperset(of: [.hero, .article, .media, .portrait, .social, .compact]))
    }

    @Test func durationsReadLikeAPlayer() {
        #expect(WebCardLayout.formatDuration(59) == "0:59")
        #expect(WebCardLayout.formatDuration(754) == "12:34")
        #expect(WebCardLayout.formatDuration(3723) == "1:02:03")
    }

    @Test func socialNamesSplitTheHandle() {
        let url = URL(string: "https://x.com/nightwatch_k/status/1")!
        let snapshot = LinkSnapshot(fetchedAt: .now, variant: .social, title: "Kemi Okafor (@nightwatch_k) on X")
        let content = WebCardContent(payload: WebPayload(url: url, snapshot: snapshot), assets: [:], isLoading: false)
        let names = WebCardLayout.socialNames(content)
        #expect(names.name == "Kemi Okafor" && names.handle == "@nightwatch_k")
    }

    @Test func textPicksTheReadableInk() {
        #expect(WebCardArt.prefersLightText(on: RGBA(0x10131A)))
        #expect(!WebCardArt.prefersLightText(on: RGBA(0xF4EBD0)))
        #expect(WebCardArt.contrast(.white, .black) > 20)
    }

    @Test func meshIsNineColorsAndDraws() {
        let palette = PaletteExtractor.palette(forDomain: "harborgazette.com")
        for full in [true, false] {
            let colors = WebCardArt.meshColors(palette: palette, appearance: Self.appearance, full: full)
            #expect(colors.count == 9)
            let image = WebCardArt.meshImage(colors)
            #expect(image?.width == 32 && image?.height == 32)
        }
    }

    #if DEBUG
    @Test func testLinksCoverEveryLayout() {
        let samples = TestLinks.make()
        let variants = Set(samples.compactMap { $0.preview?.variant })
        #expect(variants == Set(LinkVariant.allCases))
        #expect(samples.contains { $0.preview == nil })
        for sample in samples where sample.preview?.variant == .hero {
            #expect(sample.assets.image != nil && sample.assets.icon != nil)
        }
    }
    #endif

    // MARK: Invariants

    static func checkInvariants(_ layout: WebCardLayout, content: WebCardContent, width: CGFloat, name: String) {
        let card = CGRect(origin: .zero, size: layout.size)
        #expect(layout.size.width == width, "\(name): width")
        #expect(layout.size.height >= WebCardLayout.minimumSize.height && layout.size.height <= 1000, "\(name): height \(layout.size.height)")
        #expect(!layout.blocks.isEmpty, "\(name): no text")

        // Everything sits inside the card, clear of the edges.
        let safe = card.insetBy(dx: 4, dy: 4)
        for block in layout.blocks {
            #expect(block.frame.width >= 1 && block.frame.height >= 1, "\(name): empty block \(block.text.string)")
            #expect(safe.contains(block.frame), "\(name): \(block.text.string.prefix(30)) outside the card")
            #expect(block.text.length > 0, "\(name): empty text")
        }
        for part in [layout.image, layout.icon, layout.playButton, layout.durationBadge].compactMap({ $0 }) {
            #expect(safe.contains(part), "\(name): part \(part) outside the card")
        }

        // Text never overlaps other text, the icon or the image (badge text sits on the image).
        let blocks = layout.blocks.map { $0.frame.insetBy(dx: 0.5, dy: 0.5) }
        for i in blocks.indices {
            let onBadge = layout.durationBadge.map { $0.contains(layout.blocks[i].frame) } ?? false
            if let icon = layout.icon {
                #expect(!blocks[i].intersects(icon), "\(name): \(layout.blocks[i].text.string.prefix(30)) over the icon")
            }
            if let image = layout.image, !onBadge {
                #expect(!blocks[i].intersects(image), "\(name): \(layout.blocks[i].text.string.prefix(30)) over the image")
            }
            for j in blocks.indices where j > i {
                #expect(!blocks[i].intersects(blocks[j]), "\(name): \(layout.blocks[i].text.string.prefix(20)) overlaps \(layout.blocks[j].text.string.prefix(20))")
            }
        }
        if let icon = layout.icon, let image = layout.image, !content.imageIsAvatar {
            #expect(!icon.intersects(image), "\(name): icon over the image")
        }

        // A block never holds more lines than it allows.
        for block in layout.blocks {
            let font = block.text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 13)
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            #expect(block.frame.height <= lineHeight * CGFloat(block.maxLines) * 1.5 + 2, "\(name): \(block.text.string.prefix(30)) too tall")
        }

        // And it draws.
        let image = WebCardTypography.render(layout, scale: 2)
        #expect(image?.width == Int((layout.size.width * 2).rounded(.up)), "\(name): render")
    }
}
