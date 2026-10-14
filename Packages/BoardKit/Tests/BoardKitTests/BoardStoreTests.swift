import Foundation
import Testing
@testable import BoardKit

@MainActor
@Suite("Board store")
struct BoardStoreTests {
    static let stamp = Date(timeIntervalSince1970: 1_800_000_000)

    static func textCard(_ text: String, x: Double = 0, z: Int = 0) -> Card {
        Card(
            frame: Rect(x: x, y: 0, width: 200, height: 80),
            z: z,
            createdAt: stamp,
            modifiedAt: stamp,
            content: .text(TextPayload(content: text))
        )
    }

    static func sampleStore() -> (BoardStore, [Card]) {
        let cards = (0..<4).map { textCard("card \($0)", x: Double($0) * 300, z: $0) }
        var board = Board.new(title: "Test", now: stamp)
        board.cards = cards
        board.strings = [
            BoardString(from: cards[0].id, to: cards[1].id),
            BoardString(from: cards[1].id, to: cards[2].id),
            BoardString(from: cards[2].id, to: cards[3].id),
        ]
        return (BoardStore(board: board), cards)
    }

    @Test func insertAndUndo() throws {
        let (store, _) = Self.sampleStore()
        let original = store.board
        let card = Self.textCard("new", z: 9)

        let inverse = try #require(store.apply(.insertCards([card])))
        #expect(store.card(card.id) == card)
        #expect(store.maxZ == 9)

        store.apply(inverse)
        #expect(store.board == original)
        #expect(store.card(card.id) == nil)
    }

    @Test func removeTakesAttachedStringsAndUndoRestoresOrder() throws {
        let (store, cards) = Self.sampleStore()
        let original = store.board

        let inverse = try #require(store.apply(.removeCards([cards[1].id])))
        #expect(store.board.cards.count == 3)
        #expect(store.board.strings.count == 1) // only 2 → 3 survives

        store.apply(inverse)
        #expect(store.board == original)
    }

    @Test func setFramesAndUpdateCardsAreReversible() throws {
        let (store, cards) = Self.sampleStore()
        let original = store.board

        var moved = cards[0].frame
        moved.x += 40
        let undoMove = try #require(store.apply(.setFrames([cards[0].id: moved])))
        #expect(store.card(cards[0].id)?.frame == moved)

        var edited = try #require(store.card(cards[2].id))
        edited.content = .text(TextPayload(content: "edited", style: .headline))
        edited.tint = .violet
        let undoEdit = try #require(store.apply(.updateCards([edited])))
        #expect(store.card(cards[2].id) == edited)

        store.apply(undoEdit)
        store.apply(undoMove)
        #expect(store.board == original)
    }

    @Test func noOpCommandsReturnNilAndDoNotNotify() {
        let (store, cards) = Self.sampleStore()
        let notifications = Recorder()
        store.addObserver { notifications.record($0) }

        #expect(store.apply(.removeCards([UUID()])) == nil)
        #expect(store.apply(.setFrames([cards[0].id: cards[0].frame])) == nil)
        #expect(store.apply(.updateCards([cards[1]])) == nil)
        #expect(store.apply(.insertCards([cards[0]])) == nil) // already on the board
        #expect(store.apply(.insertStrings([BoardString(from: cards[0].id, to: cards[0].id)])) == nil)
        #expect(store.apply(.batch([])) == nil)
        #expect(notifications.received.isEmpty)
        #expect(store.revision == 0)
    }

    @Test func observersReceiveExactChanges() throws {
        let (store, cards) = Self.sampleStore()
        let recorder = Recorder()
        store.addObserver { recorder.record($0) }

        store.apply(.removeCards([cards[3].id]))
        let changes = try #require(recorder.received.last)
        #expect(changes.removedCards == [cards[3].id])
        #expect(changes.removedStrings.count == 1)
        #expect(changes.insertedCards.isEmpty)
    }

    @Test func randomEditsUndoBackToTheOriginal() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<20 {
            let (store, _) = Self.sampleStore()
            let original = store.board
            var undoStack: [BoardCommand] = []
            for _ in 0..<25 {
                let command = Self.randomCommand(for: store.board, using: &generator)
                if let inverse = store.apply(command) { undoStack.append(inverse) }
            }
            for inverse in undoStack.reversed() { store.apply(inverse) }
            #expect(store.board == original)
        }
    }

    @Test func redoAfterUndoReproducesTheEdit() throws {
        let (store, cards) = Self.sampleStore()
        let command = BoardCommand.batch([
            .removeCards([cards[0].id]),
            .insertCards([Self.textCard("fresh")]),
        ])
        let undo = try #require(store.apply(command))
        let afterEdit = store.board
        let redo = try #require(store.apply(undo))
        store.apply(redo)
        #expect(store.board == afterEdit)
    }

    @Test func snapshotStampsModifiedAtOnlyAfterChanges() {
        let (store, cards) = Self.sampleStore()
        let later = Self.stamp.addingTimeInterval(3600)
        #expect(store.snapshot(now: later).modifiedAt == Self.stamp)

        store.apply(.removeCards([cards[0].id]))
        #expect(store.snapshot(now: later).modifiedAt == later)
        #expect(store.snapshot(now: later.addingTimeInterval(60)).modifiedAt == later)
    }

    @Test func snapshotWorksOffTheMainThread() async throws {
        let (store, cards) = Self.sampleStore()
        store.apply(.removeCards([cards[0].id]))
        store.viewport = Viewport(x: 12, y: 34, zoom: 2)
        let snapshot = await Task.detached { store.snapshot() }.value
        #expect(snapshot.cards.count == 3)
        #expect(snapshot.viewport == Viewport(x: 12, y: 34, zoom: 2))
    }

    // MARK: - Helpers

    static func randomCommand(for board: Board, using rng: inout SeededGenerator) -> BoardCommand {
        let ids = board.cards.map(\.id)
        switch Int.random(in: 0..<6, using: &rng) {
        case 0:
            return .insertCards([textCard("random", x: Double.random(in: -500...500, using: &rng), z: Int.random(in: 0...20, using: &rng))])
        case 1 where !ids.isEmpty:
            return .removeCards([ids.randomElement(using: &rng)!])
        case 2 where ids.count >= 2:
            let pair = ids.shuffled(using: &rng).prefix(2)
            return .insertStrings([BoardString(from: pair.first!, to: pair.last!)])
        case 3 where !board.strings.isEmpty:
            return .removeStrings([board.strings.randomElement(using: &rng)!.id])
        case 4 where !ids.isEmpty:
            let id = ids.randomElement(using: &rng)!
            return .setFrames([id: Rect(x: Double.random(in: -900...900, using: &rng), y: 0, width: 120, height: 90)])
        case 5 where !board.cards.isEmpty:
            var card = board.cards.randomElement(using: &rng)!
            card.z += 1
            card.locked.toggle()
            return .updateCards([card])
        default:
            return .batch([])
        }
    }
}

/// Collects change notifications on the main actor.
@MainActor
final class Recorder {
    private(set) var received: [BoardChanges] = []

    func record(_ changes: BoardChanges) {
        received.append(changes)
    }
}

/// A tiny deterministic generator so the random-edit test is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
