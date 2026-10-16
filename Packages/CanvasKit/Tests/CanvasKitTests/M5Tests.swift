import AppKit
import Foundation
import Testing
import BoardKit
@testable import CanvasKit

@Suite("Search")
struct SearchTests {
    static func card(_ content: CardContent, x: Double = 0, y: Double = 0) -> Card {
        Card(frame: Rect(x: x, y: y, width: 200, height: 80), createdAt: .now, modifiedAt: .now, content: content)
    }

    @Test func findsTextCaptionsAndLinks() {
        let note = Self.card(.text(TextPayload(content: "The night guard saw a second boat")), y: 100)
        let photo = Self.card(.image(ImagePayload(asset: "a", caption: "Dock camera, night of the 3rd")), y: 0)
        var web = WebPayload(url: URL(string: "https://example.com/harbor-report")!)
        web.snapshot = LinkSnapshot(fetchedAt: .now, variant: .article, title: "Harbor authority releases night logs")
        let link = Self.card(.web(web), x: 300, y: 0)
        let other = Self.card(.text(TextPayload(content: "Insurance claim")), y: 50)
        let cards = [note, photo, link, other]

        // Top to bottom, then left to right.
        #expect(CardSearch.matches("night", in: cards) == [photo.id, link.id, note.id])
        // Every word must match; case and accents don't matter.
        #expect(CardSearch.matches("NIGHT boat", in: cards) == [note.id])
        #expect(CardSearch.matches("insurânce", in: cards) == [other.id])
        // Addresses count too.
        #expect(CardSearch.matches("harbor-report", in: cards) == [link.id])
        #expect(CardSearch.matches("   ", in: cards).isEmpty)
        #expect(CardSearch.matches("zebra", in: cards).isEmpty)
    }

    @Test func anEmptySearchDoesNotDim() {
        #expect(!Highlight.search(query: " ", matches: [], current: nil).dimsBoard)
        #expect(Highlight.search(query: "x", matches: [], current: nil).dimsBoard)
        #expect(Highlight.focus(seeds: [], hops: 1).dimsBoard)
    }
}

@MainActor
@Suite("Themes")
struct ThemeTests {
    @Test func themesCanRecolorTheDefaultString() {
        var appearance = TextCardTests.appearance
        appearance.tints = [.red: GradientPair(RGBA(0xFF0000), RGBA(0xFF0000)), .azure: GradientPair(.white, .white)]
        #expect(appearance.gradient(for: StringColor.tint(.red)).from == RGBA(0xFF0000))
        appearance.string = GradientPair(.white, RGBA(0x8FE3FF))
        #expect(appearance.gradient(for: StringColor.tint(.red)).to == RGBA(0x8FE3FF))
        // Other colors, and red card tints, are left alone.
        #expect(appearance.gradient(for: StringColor.tint(.azure)).from == .white)
        #expect(appearance.gradient(for: Tint.red).from == RGBA(0xFF0000))
    }

    @Test func lightCardsAreRecognized() {
        var appearance = TextCardTests.appearance
        #expect(!appearance.hasLightCards)
        appearance.cardFill = GradientPair(.white, RGBA(0xF9FAFC))
        #expect(appearance.hasLightCards)
    }

    @Test func corkGrainIsStableAndTileSized() throws {
        let first = try #require(GrainTexture.makeTile(color: RGBA(0x2E1A0B, alpha: 0.9), scale: 2))
        let second = try #require(GrainTexture.makeTile(color: RGBA(0x2E1A0B, alpha: 0.9), scale: 2))
        #expect(first.width == 512 && first.height == 512)
        #expect(first.dataProvider?.data as Data? == second.dataProvider?.data as Data?)
    }

    /// The grain is glued to the board: its tiles always cover a power-of-two fraction of
    /// 256 board points, starting at the board's origin, so zooming never slides it under
    /// the cards; and crossing a power of two in zoom changes nothing on screen.
    @Test func corkGrainZoomsWithTheBoard() {
        var zoom: CGFloat = 0.05
        while zoom < 8 {
            let octave = GrainTexture.octave(forZoom: zoom)
            let exponent = log2(Double(GrainTexture.tileSize * zoom / octave.coarseSide))
            #expect(abs(exponent - exponent.rounded()) < 1e-9, "zoom \(zoom)")
            #expect(octave.coarseSide >= 256 - 1e-9 && octave.coarseSide < 512)
            zoom *= 1.07
        }
        let below = GrainTexture.octave(forZoom: 0.5 - 1e-9)
        let at = GrainTexture.octave(forZoom: 0.5)
        #expect(abs(below.coarseSide / 2 - at.coarseSide) < 0.01)
        #expect(below.fineOpacity > 0.999 && at.fineOpacity < 0.001)
    }

    @Test func webTextStaysReadableOnLightCards() {
        var appearance = TextCardTests.appearance
        appearance.cardFill = GradientPair(.white, RGBA(0xF9FAFC))
        let palette = LinkPalette(vibrant: "#3A7BFF", muted: "#5C6A88", darkVibrant: "#12306E", darkMuted: "#1B2235", light: "#E8EEFF")
        let onCard = WebCardTypography(appearance: appearance, palette: palette, fullMesh: false)
        let onMesh = WebCardTypography(appearance: appearance, palette: palette, fullMesh: true)
        #expect(onCard.primary.usingColorSpace(.sRGB)!.brightnessComponent < 0.3)
        #expect(onMesh.primary.usingColorSpace(.sRGB)!.brightnessComponent > 0.8)
    }
}
