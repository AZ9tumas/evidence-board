import AppKit
import Testing
import BoardKit
@testable import CanvasKit

@MainActor
@Suite("Material theme rendering")
struct MaterialThemeTests {
    static let themes: [ThemeID] = [.parchment, .chalkboard, .fieldNotes, .crimeLab, .circuit, .scrapbook, .newsroom, .observatory]

    @Test func surfacesRemainDifferentWhenColorsAreIdentical() throws {
        var images = Set<Data>()
        for theme in Self.themes {
            let first = try #require(ThemeArtwork.surfaceTile(theme.texture, color: .white, scale: 1))
            let second = try #require(ThemeArtwork.surfaceTile(theme.texture, color: .white, scale: 1))
            let bytes = try #require(first.dataProvider?.data as Data?)
            #expect(bytes == second.dataProvider?.data as Data?)
            #expect(first.width == 256 && first.height == 256)
            images.insert(bytes)
        }
        #expect(images.count == Self.themes.count)
    }

    @Test(arguments: themes)
    func previewIncludesMaterialsAndPreservesTheBoard(_ theme: ThemeID) throws {
        var board = Board.new()
        board.theme = theme
        board.cards = [Card(frame: Rect(x: 0, y: 0, width: 260, height: 180), createdAt: board.createdAt,
                            modifiedAt: board.modifiedAt, content: .text(TextPayload(content: "Evidence **A**")))]
        let original = board
        let appearance = CanvasAppearance.forTheme(theme, dark: false)
        #expect(appearance.design == theme.design && appearance.texture == theme.texture)
        let image = try #require(BoardRenderer.image(of: board, appearance: appearance, maxSize: CGSize(width: 600, height: 400), scale: 1))
        #expect(image.width > 0 && image.height > 0)
        #expect(board == original)
        let ornament = ThemeArtwork.ornament(in: CGRect(x: 0, y: 0, width: 260, height: 180), style: theme.design.ornament)
        #expect(!ornament.isEmpty)
        let fastener = ThemeArtwork.fastener(theme.design.fastener, in: CGRect(x: 0, y: 0, width: 14, height: 14))
        #expect(!fastener.body.isEmpty || !fastener.detail.isEmpty)
    }

    @Test(arguments: themes)
    func typographyKeepsExplicitUserFormatting(_ theme: ThemeID) throws {
        let appearance = CanvasAppearance.forTheme(theme, dark: false)
        let text = TextPayload(content: "Evidence", fontSize: 36, bold: true, underline: true)
        let rendered = TextCardTypography.attributedText(for: text, appearance: appearance)
        let font = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 36)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(rendered.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func themeSwitchRefitsAutomaticTextWithoutOverwritingFormatting() throws {
        _ = NSApplication.shared
        var board = Board.new()
        let payload = TextPayload(content: String(repeating: "A clue worth keeping. ", count: 10), fontSize: 24, italic: true)
        board.cards = [Card(frame: Rect(x: 0, y: 0, width: 260, height: 100), createdAt: board.createdAt,
                            modifiedAt: board.modifiedAt, content: .text(payload))]
        let store = BoardStore(board: board)
        let view = BoardCanvasView(store: store, appearance: .noir)
        view.canvasAppearance = .newsroom
        #expect(store.board.cards[0].content == .text(payload))
        let expected = TextCardTypography.fittingHeight(for: payload, width: 260, appearance: .newsroom)
        #expect(store.board.cards[0].frame.height == expected)
    }
}
