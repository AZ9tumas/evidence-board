import AppKit
import Testing
import BoardKit
@testable import CanvasKit

@MainActor
@Suite("Text formatting controls")
struct TextFormattingControlTests {
    @Test func rendererCombinesCardFormattingAndMarkdown() throws {
        let text = TextPayload(content: "Plain **bold** and `code`", alignment: .center,
                               fontSize: 32, italic: true, underline: true, strikethrough: true)
        let rendered = TextCardTypography.attributedText(for: text, appearance: .parchment)
        #expect(rendered.string == "Plain bold and code")
        let plain = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let bold = try #require(rendered.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
        let code = try #require(rendered.attribute(.font, at: 16, effectiveRange: nil) as? NSFont)
        #expect(plain.pointSize == 32 && plain.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(bold.fontDescriptor.symbolicTraits.contains([.bold, .italic]))
        #expect(code.isFixedPitch && code.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(rendered.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(rendered.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect((rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .center)
    }

    @Test func largerTextGrowsAutoHeightCards() {
        let small = TextPayload(content: "A long clue that should wrap over several lines on the card.")
        var large = small
        large.fontSize = 48
        #expect(TextCardTypography.fittingHeight(for: large, width: 260, appearance: .forest)
                > TextCardTypography.fittingHeight(for: small, width: 260, appearance: .forest))
    }

    @Test func selectionFormattingSkipsLockedCardsAndSupportsUndo() throws {
        let fixture = Fixture()
        fixture.view.select(Set(fixture.store.board.cards.map(\.id)))
        let before = fixture.store.board
        fixture.undo.beginUndoGrouping()
        fixture.controller.setTextFontSize(48)
        fixture.undo.endUndoGrouping()
        #expect(fixture.controller.selectedTextPayloads.count == 1)
        #expect(fixture.controller.selectedTextPayloads.first?.fontSize == 48)
        #expect(fixture.store.board.cards[0].frame.height > before.cards[0].frame.height)
        #expect(fixture.store.board.cards[1] == before.cards[1])
        #expect(fixture.store.board.cards[2] == before.cards[2])
        fixture.undo.undo()
        #expect(fixture.store.board == before)
        #expect(fixture.controller.selectedTextPayloads.first?.fontSize == nil)
        fixture.undo.redo()
        #expect(fixture.controller.selectedTextPayloads.first?.fontSize == 48)
    }

    @Test func formattingWhileTypingPreservesSelectionAndCommitsOnce() throws {
        let fixture = Fixture()
        let id = fixture.store.board.cards[0].id
        let original = fixture.store.board
        fixture.view.beginEditing(id, isNewCard: false, selectAll: false)
        let editor = try #require(fixture.view.textEditor)
        let textView = try #require(editor.scrollView.documentView as? NSTextView)
        let selection = NSRange(location: 2, length: 3)
        textView.setSelectedRange(selection)
        fixture.controller.setTextFormat(.bold, enabled: true)
        fixture.controller.setTextFontSize(32)
        fixture.controller.setTextAlignment(.trailing)
        #expect(fixture.view.textEditor === editor)
        #expect(textView.selectedRange() == selection)
        #expect(fixture.store.board == original) // Still a live edit.
        #expect(fixture.controller.textFormatIsEnabled(.bold))
        #expect(fixture.controller.selectedTextPayloads.first?.fontSize == 32)
        let font = try #require(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 32 && font.fontDescriptor.symbolicTraits.contains(.bold))
        fixture.undo.beginUndoGrouping()
        fixture.view.finishEditing()
        fixture.undo.endUndoGrouping()
        guard case .text(let saved) = fixture.store.board.cards[0].content else {
            Issue.record("Expected text card")
            return
        }
        #expect(saved.fontSize == 32 && saved.isEnabled(.bold) && saved.alignment == .trailing)
        #expect(saved.content == "An important clue")
        fixture.undo.undo()
        #expect(fixture.store.board == original)
    }

    @Test func localFormattingUndoRestoresPayloadAndRedo() throws {
        let fixture = Fixture()
        fixture.view.beginEditing(fixture.store.board.cards[0].id, isNewCard: false, selectAll: false)
        let editor = try #require(fixture.view.textEditor)
        let textView = try #require(editor.scrollView.documentView as? NSTextView)
        let undo = try #require(editor.undoManager(for: textView))
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        fixture.controller.setTextFormat(.italic, enabled: true)
        undo.endUndoGrouping()
        #expect(fixture.controller.textFormatIsEnabled(.italic))
        undo.undo()
        #expect(!fixture.controller.textFormatIsEnabled(.italic))
        #expect(textView.string == "An important clue")
        undo.redo()
        #expect(fixture.controller.textFormatIsEnabled(.italic))
        fixture.view.tearDownEditor()
    }

    @Test func anEmptyCardKeepsFormattingWhenTypingStarts() throws {
        let fixture = Fixture()
        fixture.view.createTextCard(at: .zero)
        let editor = try #require(fixture.view.textEditor)
        let textView = try #require(editor.scrollView.documentView as? NSTextView)
        fixture.controller.setTextFontSize(36)
        fixture.controller.setTextFormat(.bold, enabled: true)
        fixture.controller.setTextFormat(.underline, enabled: true)
        let typingFont = try #require(textView.typingAttributes[.font] as? NSFont)
        #expect(typingFont.pointSize == 36 && typingFont.fontDescriptor.symbolicTraits.contains(.bold))
        textView.insertText("New clue", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(fixture.controller.selectedTextPayloads.first?.content == "New clue")
        fixture.undo.beginUndoGrouping()
        fixture.view.finishEditing()
        fixture.undo.endUndoGrouping()
        guard case .text(let saved) = fixture.store.card(editor.cardID)?.content else {
            Issue.record("Expected text card")
            return
        }
        #expect(saved.fontSize == 36 && saved.isEnabled(.bold) && saved.underline)
        #expect(saved.content == "New clue")
    }

    @MainActor
    private final class Fixture {
        let store: BoardStore
        let view: BoardCanvasView
        let controller: CanvasController
        let undo = UndoManager()
        let window: NSWindow

        init() {
            _ = NSApplication.shared
            var board = Board.new()
            func card(_ content: CardContent, locked: Bool = false) -> Card {
                Card(frame: Rect(x: 0, y: 0, width: 260, height: 100), locked: locked,
                     createdAt: board.createdAt, modifiedAt: board.modifiedAt, content: content)
            }
            board.cards = [card(.text(TextPayload(content: "An important clue"))),
                           card(.text(TextPayload(content: "Locked clue")), locked: true),
                           card(.web(WebPayload(url: URL(string: "https://example.com")!)))]
            store = BoardStore(board: board)
            controller = CanvasController(store: store)
            view = BoardCanvasView(store: store, appearance: .forest)
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let container = NSView(frame: window.contentView!.bounds)
            window.contentView = container
            view.frame = container.bounds
            container.addSubview(view)
            controller.attach(view)
            undo.groupsByEvent = false
            view.boardEditor.undoManager = undo
        }
    }
}
