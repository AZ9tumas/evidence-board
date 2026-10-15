import AppKit
import Foundation
import Testing
import BoardKit
@testable import CanvasKit

@Suite("Theme contrast")
struct ThemeContrastTests {
    static let themes: [(String, CanvasAppearance)] = [
        ("Noir", .noir), ("Cork", .cork), ("Blueprint", .blueprint), ("Daylight", .daylight),
    ]

    /// `color` laid over `backdrop`, for translucent fills.
    static func over(_ color: RGBA, _ backdrop: RGBA) -> RGBA {
        color.opacity(1).mixed(with: backdrop.opacity(1), 1 - color.alpha)
    }

    /// All card text meets WCAG AA (4.5:1) on every theme, on both ends of each gradient
    /// and over both ends of the board for translucent fills (DESIGN.md §14).
    @Test(arguments: themes.map(\.0))
    func textMeetsAA(_ name: String) {
        let appearance = Self.themes.first { $0.0 == name }!.1
        let boards = [appearance.background.from, appearance.background.to]
        func check(_ ink: RGBA, on fill: GradientPair, _ what: String) {
            for paint in [fill.from, fill.to] {
                for board in boards {
                    let ratio = WebCardArt.contrast(ink, Self.over(paint, board))
                    #expect(ratio >= 4.5, "\(name) \(what): \(ratio)")
                }
            }
        }
        check(appearance.text, on: appearance.cardFill, "card text")
        check(appearance.paperText, on: appearance.paperFill, "typewriter text")
        check(appearance.captionInk, on: appearance.photoPaper, "captions")
        check(appearance.labelText, on: appearance.labelFill, "string labels")
        for case let hostile in [appearance.adjusted(increaseContrast: true, reduceTransparency: true)] {
            check(hostile.text, on: hostile.cardFill, "card text, Increase Contrast")
        }
    }

    @Test func increaseContrastAndReduceTransparency() {
        let base = CanvasAppearance.blueprint
        let contrast = base.adjusted(increaseContrast: true, reduceTransparency: false)
        #expect(contrast.cardStroke.from.alpha == 0.4 && contrast.cardStroke.to.alpha == 0.4)
        #expect(contrast.stringBoost == 1)
        let solid = base.adjusted(increaseContrast: false, reduceTransparency: true)
        #expect(base.cardFill.from.alpha < 1 && solid.cardFill.from.alpha == 1 && solid.labelFill.to.alpha == 1)
        #expect(solid.stringBoost == 0 && solid.cardStroke == base.cardStroke)
        #expect(base.adjusted(increaseContrast: false, reduceTransparency: false) == base)
    }
}

/// VoiceOver's view of the board, and moving around it with the keyboard.
@MainActor
@Suite("Accessibility")
struct AccessibilityTests {
    let store: BoardStore
    let cards: [Card]
    let view: BoardCanvasView
    let window: NSWindow

    init() {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        func card(_ x: Double, _ y: Double, _ content: CardContent, locked: Bool = false) -> Card {
            Card(frame: Rect(x: x, y: y, width: 200, height: 100), locked: locked, createdAt: stamp, modifiedAt: stamp, content: content)
        }
        var web = WebPayload(url: URL(string: "https://www.example.com/report")!)
        web.snapshot = LinkSnapshot(fetchedAt: stamp, variant: .article, title: "Harbor authority releases night logs")
        cards = [
            card(400, 0, .image(ImagePayload(asset: "a", caption: "Dock camera, 23:41"))),
            card(0, 0, .text(TextPayload(content: "Ferry left **11 minutes early**\nWho changed it?")), locked: true),
            card(0, 300, .web(web)),
        ]
        var board = Board.new(title: "A11y", now: stamp)
        board.cards = cards
        board.strings = [
            BoardString(from: cards[1].id, to: cards[0].id, stroke: .dashed, label: "same night"),
            BoardString(from: cards[0].id, to: cards[2].id, arrow: .forward),
        ]
        store = BoardStore(board: board)
        _ = NSApplication.shared
        view = BoardCanvasView(store: store, appearance: TextCardTests.appearance)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.setCamera(Camera(center: CGPoint(x: 300, y: 200), zoom: 1))
    }

    func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        )!
        view.keyDown(with: event)
    }

    @Test func everyCardAndStringIsAnElement() throws {
        let children = try #require(view.accessibilityChildren())
        #expect(children.count == 5)
        #expect(view.accessibilityRole() == .layoutArea)
        #expect(view.accessibilityLabel() == "Board, 3 cards, 2 strings")

        // Cards come first, in reading order: the text card (top left), the photo, the link.
        let elements = children.compactMap { $0 as? CardAccessibilityElement }
        #expect(elements.map(\.cardID) == [cards[1].id, cards[0].id, cards[2].id])
        #expect(elements[0].accessibilityLabel() == "Text card: Ferry left 11 minutes early\nWho changed it?, locked, 1 connection")
        #expect(elements[1].accessibilityLabel() == "Photo: Dock camera, 23:41, 2 connections")
        #expect(elements[2].accessibilityLabel() == "Web card: Harbor authority releases night logs, example.com, 1 connection")
        #expect(elements[0].accessibilityRoleDescription() == "text card")
        #expect(elements[0].accessibilityFrame().width > 150)

        let strings = children.compactMap { $0 as? StringAccessibilityElement }
        #expect(strings.map { $0.accessibilityLabel() ?? "" } == [
            "String from Ferry left 11 minutes early to Dock camera, 23:41, labelled same night, dashed",
            "String from Dock camera, 23:41 to Harbor authority releases night logs, pointing to Harbor authority releases night logs",
        ])
        // The same objects come back, so VoiceOver keeps its place.
        #expect(view.accessibilityChildren()?.first as AnyObject? === elements[0])
    }

    @Test func cardsHaveActionsAndAConnectionsRotor() throws {
        let photo = try #require(view.accessibilityElement(forCard: cards[0].id))
        let names = try #require(photo.accessibilityCustomActions()).map(\.name)
        #expect(names.contains("Edit Caption") && names.contains("Delete") && names.contains("Lock"))
        let web = try #require(view.accessibilityElement(forCard: cards[2].id))
        #expect(try #require(web.accessibilityCustomActions()).map(\.name).contains("Open in Browser"))

        let rotor = try #require(photo.accessibilityCustomRotors().first)
        #expect(rotor.label == "Connections")
        let parameters = NSAccessibilityCustomRotor.SearchParameters()
        parameters.searchDirection = .next
        let first = try #require(photo.rotor(rotor, resultFor: parameters))
        parameters.currentItem = first
        let second = try #require(photo.rotor(rotor, resultFor: parameters))
        parameters.currentItem = second
        #expect(photo.rotor(rotor, resultFor: parameters) == nil)
        let found = [first, second].compactMap { ($0.targetElement as? StringAccessibilityElement)?.stringID }
        #expect(Set(found) == Set(store.board.strings.map(\.id)))

        // Pressing a card selects it.
        #expect(photo.accessibilityPerformPress())
        #expect(view.selection == [cards[0].id])
    }

    @Test func tabWalksTheCardsInReadingOrder() {
        key(48, "\t")
        #expect(view.selection == [cards[1].id])
        key(48, "\t")
        #expect(view.selection == [cards[0].id])
        key(48, "\t")
        #expect(view.selection == [cards[2].id])
        key(48, "\t")
        #expect(view.selection == [cards[1].id]) // around again
        key(48, "\t", .shift)
        #expect(view.selection == [cards[2].id])
    }

    @Test func optionArrowsMoveToTheNearestCardThatWay() {
        view.select([cards[1].id])
        key(124, "\u{F703}", .option) // right
        #expect(view.selection == [cards[0].id])
        key(125, "\u{F701}", .option) // down: the link is below and left, the only card that way
        #expect(view.selection == [cards[2].id])
        key(126, "\u{F700}", .option) // up
        #expect(view.selection == [cards[1].id])
        // Plain arrows still nudge (the photo; the text card is locked).
        view.select([cards[0].id])
        let before = store.card(cards[0].id)!.frame.x
        key(124, "\u{F703}")
        #expect(store.card(cards[0].id)!.frame.x == before + 1)
    }

    @Test func commandKTiesTheLastTwoFocusedCards() {
        view.select([cards[1].id])
        view.select([cards[2].id])
        #expect(view.previouslyFocusedCard == cards[1].id)
        view.connectSelection()
        #expect(store.board.strings.contains { $0.from == cards[1].id && $0.to == cards[2].id })
    }
}
