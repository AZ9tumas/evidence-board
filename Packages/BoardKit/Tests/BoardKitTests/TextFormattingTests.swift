import Foundation
import Testing
@testable import BoardKit

@Suite("Text formatting persistence")
struct TextFormattingTests {
    static func board(with text: TextPayload) -> Board {
        var board = Board.new()
        board.cards = [Card(frame: Rect(x: 0, y: 0, width: 260, height: 100),
                            createdAt: board.createdAt, modifiedAt: board.modifiedAt, content: .text(text))]
        return board
    }

    @Test(arguments: TextCardStyle.allCases)
    func oldPayloadsKeepTheirOriginalAppearance(_ style: TextCardStyle) throws {
        let data = Data("{\"content\":\"Legacy note\",\"style\":\"\(style.rawValue)\"}".utf8)
        let text = try JSONDecoder().decode(TextPayload.self, from: data)
        #expect(text.fontSize == nil && text.bold == nil)
        #expect(text.resolvedFontSize == style.defaultFontSize)
        #expect(text.isEnabled(.bold) == (style == .headline))
        #expect(!text.italic && !text.underline && !text.strikethrough)
    }

    @Test(arguments: [ThemeID.fieldNotes, .observatory, .parchment])
    func themesAndFormattingSurviveSavingAndCopying(_ theme: ThemeID) throws {
        let text = TextPayload(content: "Clue **one**", style: .typewriter, alignment: .center,
                               fontSize: 36, bold: true, italic: true, underline: true, strikethrough: true)
        var board = Self.board(with: text)
        board.theme = theme
        let loaded = try BoardCodec.decode(BoardCodec.encode(board))
        #expect(loaded.report == LoadReport())
        #expect(loaded.board == board)
        let clip = BoardClip(copying: Set(board.cards.map(\.id)), from: board)
        let copied = try BoardCodec.decodeClip(BoardCodec.encodeClip(clip)).instantiated(dx: 24, dy: 24, baseZ: 1)
        #expect(copied.cards.first?.content == .text(text))
        #expect(copied.cards.first?.id != board.cards.first?.id)
    }

    @Test func explicitRegularWeightOverridesHeadlineDefault() throws {
        let text = TextPayload(content: "Headline", style: .headline, bold: false)
        let loaded = try BoardCodec.decode(BoardCodec.encode(Self.board(with: text)))
        guard case .text(let decoded) = loaded.board.cards[0].content else {
            Issue.record("Expected text card")
            return
        }
        #expect(decoded.bold == false)
        #expect(!decoded.isEnabled(.bold))
    }

    @Test(arguments: [-100.0, 10000.0])
    func loadedFontSizesAreRepairedAndStabilize(_ size: Double) throws {
        let board = Self.board(with: TextPayload(content: "Clue", fontSize: size))
        let loaded = try BoardCodec.decode(BoardCodec.encode(board))
        #expect(loaded.report.adjustedValues == 1)
        guard case .text(let text) = loaded.board.cards[0].content else {
            Issue.record("Expected text card")
            return
        }
        #expect(text.fontSize == (size < 8 ? 8 : 96))
        let again = try BoardCodec.decode(BoardCodec.encode(loaded.board))
        #expect(again.report == LoadReport())
        #expect(again.board == loaded.board)
    }

    @Test func resetKeepsContentAndManualHeight() {
        var text = TextPayload(content: "Keep **inline emphasis**", style: .headline, alignment: .trailing,
                               autoHeight: false, fontSize: 48, bold: false, italic: true, underline: true, strikethrough: true)
        text.resetFormatting()
        #expect(text == TextPayload(content: "Keep **inline emphasis**", autoHeight: false))
    }

    @MainActor
    @Test func formattingAndThemeUndoRestoreTheBoard() throws {
        let original = Self.board(with: TextPayload(content: "Clue"))
        let store = BoardStore(board: original)
        var updated = original.cards[0]
        updated.content = .text(TextPayload(content: "Clue", fontSize: 32, bold: true, underline: true))
        let undo = try #require(store.apply(.batch([.updateCards([updated]), .setTheme(.fieldNotes)])))
        let edited = store.board
        let redo = try #require(store.apply(undo))
        #expect(store.board == original)
        store.apply(redo)
        #expect(store.board == edited)
    }
}
