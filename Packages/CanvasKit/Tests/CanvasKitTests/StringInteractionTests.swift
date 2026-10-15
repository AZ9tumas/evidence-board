import AppKit
import Foundation
import Testing
import BoardKit
@testable import CanvasKit

/// Drives a real canvas in an offscreen window with synthesized mouse events, so the string
/// gestures are checked end to end without a person at the trackpad.
@MainActor
@Suite("String interactions")
struct StringInteractionTests {
    let store: BoardStore
    let cards: [Card]
    let view: BoardCanvasView
    let window: NSWindow

    init() {
        self.init(connected: false)
    }

    /// Three text cards in a row, 400 pt apart, optionally tied 0 → 1 → 2.
    init(connected: Bool) {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        cards = (0..<3).map { index in
            Card(
                frame: Rect(x: Double(index) * 400, y: 0, width: 200, height: 100), z: index,
                createdAt: stamp, modifiedAt: stamp, content: .text(TextPayload(content: "card \(index)"))
            )
        }
        var board = Board.new(title: "Strings", now: stamp)
        board.cards = cards
        if connected {
            board.strings = [
                BoardString(from: cards[0].id, to: cards[1].id),
                BoardString(from: cards[1].id, to: cards[2].id),
            ]
        }
        store = BoardStore(board: board)
        _ = NSApplication.shared
        view = BoardCanvasView(store: store, appearance: TextCardTests.appearance)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.setCamera(Camera(center: CGPoint(x: 500, y: 50), zoom: 1))
    }

    func mouse(_ type: NSEvent.EventType, at world: CGPoint, clicks: Int = 1) -> NSEvent {
        let point = view.convert(view.camera.worldToView(world, in: view.bounds.size), to: nil)
        return NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
        )!
    }

    func drag(from start: CGPoint, to end: CGPoint) {
        view.mouseDown(with: mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)))
        view.mouseDragged(with: mouse(.leftMouseDragged, at: end))
        view.mouseUp(with: mouse(.leftMouseUp, at: end))
    }

    func pin(_ index: Int) -> CGPoint {
        CanvasGeometry.pinPoint(of: cards[index])
    }

    @Test func draggingFromAPinOntoACardTiesAString() throws {
        drag(from: pin(0), to: CGPoint(x: 480, y: 60))
        let string = try #require(store.board.strings.first)
        #expect(store.board.strings.count == 1)
        #expect(string.from == cards[0].id && string.to == cards[1].id)
        #expect(view.connection == nil)
        #expect(view.stringNodes[string.id] != nil)
    }

    @Test func aPinNearbyPullsTheStringIn() {
        // Let go just above card 2, close to its pin but not on the card.
        drag(from: pin(0), to: CGPoint(x: pin(2).x + 12, y: -14))
        #expect(store.board.strings.map(\.to) == [cards[2].id])
    }

    @Test func lettingGoOnEmptyCanvasTiesNothing() {
        drag(from: pin(0), to: CGPoint(x: 300, y: 400))
        #expect(store.board.strings.isEmpty)
        #expect(view.connection == nil)
    }

    @Test func draggingACardStillMovesIt() {
        drag(from: CGPoint(x: 100, y: 70), to: CGPoint(x: 140, y: 120))
        #expect(store.board.strings.isEmpty)
        #expect(store.card(cards[0].id)?.frame.x == 40)
    }

    @Test func clickingAStringSelectsItAndDeleteRemovesIt() throws {
        let test = StringInteractionTests(connected: true)
        let string = test.store.board.strings[0]
        let middle = try #require(test.view.stringNodes[string.id]).curve.point(at: 0.5)
        test.view.mouseDown(with: test.mouse(.leftMouseDown, at: middle))
        test.view.mouseUp(with: test.mouse(.leftMouseUp, at: middle))
        #expect(test.view.selectedStrings == [string.id])
        #expect(test.view.selection.isEmpty)

        test.view.deleteSelection()
        #expect(test.store.board.strings.count == 1)
        #expect(test.store.string(string.id) == nil)
        #expect(test.view.selectedStrings.isEmpty)
    }

    @Test func draggingAStringDownLoosensIt() throws {
        let test = StringInteractionTests(connected: true)
        let string = test.store.board.strings[0]
        let middle = try #require(test.view.stringNodes[string.id]).curve.point(at: 0.5)
        // 400 pt apart: droop cap 72, so 27 pt down is +0.5 sag.
        test.drag(from: middle, to: CGPoint(x: middle.x, y: middle.y + 27))
        #expect(test.store.string(string.id)?.sag == 1)
        let newMiddle = try #require(test.view.stringNodes[string.id]).curve.point(at: 0.5)
        #expect(abs(newMiddle.y - middle.y - 27) < 0.5)
    }

    @Test func commandKConnectsTwoCardsAndTraceFindsThePath() throws {
        let test = StringInteractionTests(connected: true)
        test.view.select([test.cards[0].id, test.cards[2].id])

        test.view.traceSelection()
        #expect(test.view.highlight == .trace(from: test.cards[0].id, to: test.cards[2].id))
        #expect(test.view.tracePath?.cards == test.cards.map(\.id))
        #expect(test.view.highlightedStrings.count == 2)
        #expect(test.view.stringNodes.values.allSatisfy { $0.emphasis == .glowing })

        test.view.escape()
        #expect(test.view.highlight == nil)
        #expect(test.view.stringNodes.values.allSatisfy { $0.emphasis == .normal })

        test.view.connectSelection()
        let shortcut = try #require(test.store.board.strings.last)
        #expect(test.store.board.strings.count == 3)
        #expect(shortcut.from == test.cards[0].id && shortcut.to == test.cards[2].id)
        test.view.traceSelection()
        #expect(test.view.tracePath?.strings == [shortcut.id])
    }

    @Test func focusWidensOneHopAtATime() {
        let test = StringInteractionTests(connected: true)
        test.view.select([test.cards[0].id])
        test.view.focusSelection()
        #expect(test.view.highlightedCards == [test.cards[0].id, test.cards[1].id])
        let dimmed = test.view.stringNodes.values.filter { $0.emphasis == .dimmed }
        #expect(dimmed.map(\.string.from) == [test.cards[1].id])

        test.view.focusSelection()
        #expect(test.view.highlightedCards == Set(test.cards.map(\.id)))
        #expect(test.view.highlight == .focus(seeds: [test.cards[0].id], hops: 2))

        // Nothing more to reach: stays at two hops.
        test.view.focusSelection()
        #expect(test.view.highlight == .focus(seeds: [test.cards[0].id], hops: 2))
    }

    @Test func connectToolPullsFromAnywhereOnACard() {
        view.setTool(.connect)
        drag(from: CGPoint(x: 60, y: 80), to: CGPoint(x: 880, y: 60))
        #expect(store.board.strings.map(\.to) == [cards[2].id])
        view.escape()
        #expect(view.tool == .select)
    }
}
