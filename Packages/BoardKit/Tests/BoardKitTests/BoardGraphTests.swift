import Foundation
import Testing
@testable import BoardKit

@Suite("Board graph")
struct BoardGraphTests {
    /// Cards 0…n-1 with strings given as index pairs.
    static func graph(_ count: Int, _ pairs: [(Int, Int)]) -> (BoardGraph, [UUID], [BoardString]) {
        let cards = (0..<count).map { _ in UUID() }
        let strings = pairs.map { BoardString(from: cards[$0.0], to: cards[$0.1]) }
        return (BoardGraph(strings: strings), cards, strings)
    }

    @Test func findsTheShortestChainIgnoringDirection() throws {
        // 0 → 1 → 2 → 3, plus a shortcut 3 → 0 drawn the other way.
        let (graph, cards, strings) = Self.graph(5, [(0, 1), (1, 2), (2, 3), (3, 0)])
        let path = try #require(graph.shortestPath(from: cards[2], to: cards[0]))
        #expect(path.cards.count == 3)
        #expect(path.cards.first == cards[2] && path.cards.last == cards[0])
        #expect(path.strings.count == 2)

        let long = try #require(graph.shortestPath(from: cards[0], to: cards[2]))
        #expect(Set(long.strings).isSubset(of: Set(strings.map(\.id))))
        #expect(long.strings.count == 2)
    }

    @Test func pathStringsJoinConsecutiveCards() throws {
        let (graph, cards, strings) = Self.graph(6, [(0, 1), (2, 1), (2, 3), (4, 3), (4, 5)])
        let path = try #require(graph.shortestPath(from: cards[0], to: cards[5]))
        #expect(path.cards == cards)
        let byID = Dictionary(uniqueKeysWithValues: strings.map { ($0.id, $0) })
        for (offset, id) in path.strings.enumerated() {
            let string = try #require(byID[id])
            #expect(Set([string.from, string.to]) == Set([path.cards[offset], path.cards[offset + 1]]))
        }
    }

    @Test func unconnectedCardsHaveNoPath() {
        let (graph, cards, _) = Self.graph(4, [(0, 1), (2, 3)])
        #expect(graph.shortestPath(from: cards[0], to: cards[3]) == nil)
        #expect(graph.shortestPath(from: cards[0], to: UUID()) == nil)
        #expect(graph.shortestPath(from: cards[1], to: cards[1]) == GraphPath(cards: [cards[1]], strings: []))
    }

    @Test func neighborhoodWidensOneHopAtATime() {
        // A chain 0 - 1 - 2 - 3 with a spur 1 - 4.
        let (graph, cards, strings) = Self.graph(5, [(0, 1), (1, 2), (2, 3), (1, 4)])
        let one = graph.neighborhood(of: [cards[1]], hops: 1)
        #expect(one.cards == [cards[0], cards[1], cards[2], cards[4]])
        #expect(one.strings == [strings[0].id, strings[1].id, strings[3].id])
        #expect(one.canWiden)

        let two = graph.neighborhood(of: [cards[1]], hops: 2)
        #expect(two.cards == Set(cards))
        #expect(two.strings == Set(strings.map(\.id)))
        #expect(!two.canWiden)
    }

    @Test func neighborhoodIncludesStringsBetweenNeighbors() {
        // A triangle: focusing on 0 also lights up the 1 - 2 string.
        let (graph, cards, strings) = Self.graph(3, [(0, 1), (0, 2), (1, 2)])
        let focus = graph.neighborhood(of: [cards[0]], hops: 1)
        #expect(focus.strings == Set(strings.map(\.id)))
        #expect(!focus.canWiden)
    }

    @Test func lonelySeedsStayInTheNeighborhood() {
        let (graph, _, _) = Self.graph(2, [(0, 1)])
        let loner = UUID()
        let focus = graph.neighborhood(of: [loner], hops: 3)
        #expect(focus.cards == [loner])
        #expect(focus.strings.isEmpty)
        #expect(!focus.canWiden)
        #expect(graph.degree(of: loner) == 0)
    }

    /// DESIGN.md §16, M3 exit criterion: Trace on a 1,000-string board in under 5 ms.
    @Test func traceOnAThousandStringsIsFast() throws {
        var rng = SeededGenerator(seed: 7)
        let cardCount = 400
        // A long chain guarantees a path; random extra strings make it a tangle.
        var pairs = (0..<(cardCount - 1)).map { ($0, $0 + 1) }
        while pairs.count < 1_000 {
            let a = Int.random(in: 0..<cardCount, using: &rng)
            let b = Int.random(in: 0..<cardCount, using: &rng)
            if a != b { pairs.append((a, b)) }
        }
        let cards = (0..<cardCount).map { _ in UUID() }
        let strings = pairs.map { BoardString(from: cards[$0.0], to: cards[$0.1]) }

        let clock = ContinuousClock()
        var best = Duration.seconds(1)
        var path: GraphPath?
        for _ in 0..<5 {
            let elapsed = clock.measure {
                // Build and search together, as Trace does after an edit.
                let graph = BoardGraph(strings: strings)
                path = graph.shortestPath(from: cards[0], to: cards[cardCount - 1])
            }
            best = min(best, elapsed)
        }
        #expect(path != nil)
        #expect(best < .milliseconds(5), "Trace took \(best)")
    }
}
