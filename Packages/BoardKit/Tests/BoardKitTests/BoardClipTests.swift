import Foundation
import Testing
@testable import BoardKit

@MainActor
@Suite("Board clip")
struct BoardClipTests {
    @Test func copiesSelectionWithInnerStringsAndAssets() throws {
        let board = try BoardCodec.decode(Data(contentsOf: BoardCodecTests.sampleURL)).board
        // The note, the image and the web card: two strings run between them, one leaves.
        let ids = Set([board.cards[1].id, board.cards[2].id, board.cards[3].id])
        let clip = BoardClip(copying: ids, from: board)

        #expect(clip.cards.count == 3)
        #expect(clip.strings.count == 2)
        #expect(clip.assets.count == 3) // the photo plus the web card's image and icon
    }

    @Test func instantiateGivesFreshIDsAndRemapsStrings() throws {
        let board = try BoardCodec.decode(Data(contentsOf: BoardCodecTests.sampleURL)).board
        let clip = BoardClip(copying: Set(board.cards.map(\.id)), from: board)
        let copy = clip.instantiated(dx: 24, dy: 24, baseZ: 100)

        let oldIDs = Set(board.cards.map(\.id))
        let newIDs = Set(copy.cards.map(\.id))
        #expect(oldIDs.isDisjoint(with: newIDs))
        #expect(copy.cards[0].frame.x == board.cards[0].frame.x + 24)
        #expect(Set(copy.cards.map(\.z)) == Set(100..<105))
        for string in copy.strings {
            #expect(newIDs.contains(string.from) && newIDs.contains(string.to))
        }

        // The copy pastes cleanly next to the original.
        let store = BoardStore(board: board)
        store.apply(copy.insertCommand)
        #expect(store.board.cards.count == 10)
        #expect(store.board.strings.count == 6)
    }

    @Test func clipRoundTripsThroughJSON() throws {
        let board = try BoardCodec.decode(Data(contentsOf: BoardCodecTests.sampleURL)).board
        let clip = BoardClip(copying: [board.cards[2].id], from: board)
        #expect(try BoardCodec.decodeClip(BoardCodec.encodeClip(clip)) == clip)
    }

    @Test func boundsCoverEveryCard() {
        let a = BoardStoreTests.textCard("a", x: -100)
        let b = BoardStoreTests.textCard("b", x: 400)
        #expect(BoardClip(cards: [a, b]).bounds == Rect(x: -100, y: 0, width: 700, height: 80))
        #expect(BoardClip(cards: []).bounds == nil)
    }
}
