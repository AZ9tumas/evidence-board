import Foundation

/// A board's strings seen as an undirected graph of cards, for Focus and Trace.
///
/// Card IDs are mapped to small integers once, so searches run over plain arrays. Building
/// the graph and finding a path on a 1,000-string board takes well under a millisecond.
public struct BoardGraph: Sendable {
    private struct Edge: Sendable {
        let node: Int
        let string: UUID
    }

    private let cards: [UUID]
    private let index: [UUID: Int]
    private let adjacency: [[Edge]]

    /// Cards without strings aren't part of the graph; searches treat them as islands.
    public init(strings: [BoardString]) {
        var cards: [UUID] = []
        var index: [UUID: Int] = [:]
        var adjacency: [[Edge]] = []
        func node(_ id: UUID) -> Int {
            if let existing = index[id] { return existing }
            index[id] = cards.count
            cards.append(id)
            adjacency.append([])
            return cards.count - 1
        }
        for string in strings where string.from != string.to {
            let a = node(string.from)
            let b = node(string.to)
            adjacency[a].append(Edge(node: b, string: string.id))
            adjacency[b].append(Edge(node: a, string: string.id))
        }
        self.cards = cards
        self.index = index
        self.adjacency = adjacency
    }

    /// How many strings touch `card`.
    public func degree(of card: UUID) -> Int {
        index[card].map { adjacency[$0].count } ?? 0
    }

    /// Everything within `hops` strings of `seeds`: the cards, and the strings between them.
    public func neighborhood(of seeds: Set<UUID>, hops: Int) -> Neighborhood {
        var visited = [Bool](repeating: false, count: cards.count)
        var frontier: [Int] = []
        for seed in seeds {
            guard let node = index[seed], !visited[node] else { continue }
            visited[node] = true
            frontier.append(node)
        }
        var depth = 0
        while depth < max(hops, 0), !frontier.isEmpty {
            var next: [Int] = []
            for node in frontier {
                for edge in adjacency[node] where !visited[edge.node] {
                    visited[edge.node] = true
                    next.append(edge.node)
                }
            }
            frontier = next
            depth += 1
        }
        // One more step finds out whether widening would reach anything new.
        let canWiden = frontier.contains { node in adjacency[node].contains { !visited[$0.node] } }

        var result = Neighborhood(cards: seeds, strings: [], canWiden: canWiden)
        for (node, isVisited) in visited.enumerated() where isVisited {
            result.cards.insert(cards[node])
            for edge in adjacency[node] where visited[edge.node] {
                result.strings.insert(edge.string)
            }
        }
        return result
    }

    /// The shortest chain of strings from one card to another, ignoring direction, or `nil`
    /// if they aren't connected. Ties go to strings that come first in the file.
    public func shortestPath(from start: UUID, to end: UUID) -> GraphPath? {
        if start == end { return GraphPath(cards: [start], strings: []) }
        guard let source = index[start], let target = index[end] else { return nil }
        var parent = [Int](repeating: -1, count: cards.count)
        var via = [UUID?](repeating: nil, count: cards.count)
        parent[source] = source
        var queue = [source]
        var head = 0
        search: while head < queue.count {
            let node = queue[head]
            head += 1
            for edge in adjacency[node] where parent[edge.node] < 0 {
                parent[edge.node] = node
                via[edge.node] = edge.string
                if edge.node == target { break search }
                queue.append(edge.node)
            }
        }
        guard parent[target] >= 0 else { return nil }

        var path = GraphPath(cards: [end], strings: [])
        var node = target
        while node != source, let string = via[node] {
            path.strings.append(string)
            node = parent[node]
            path.cards.append(cards[node])
        }
        path.cards.reverse()
        path.strings.reverse()
        return path
    }
}

/// The result of a Focus search.
public struct Neighborhood: Sendable, Equatable {
    public var cards: Set<UUID>
    public var strings: Set<UUID>
    /// Whether one more hop would reach more cards.
    public var canWiden: Bool

    public init(cards: Set<UUID>, strings: Set<UUID>, canWiden: Bool) {
        self.cards = cards
        self.strings = strings
        self.canWiden = canWiden
    }
}

/// A chain of strings from one card to another. `strings[i]` joins `cards[i]` and `cards[i + 1]`.
public struct GraphPath: Sendable, Equatable {
    public var cards: [UUID]
    public var strings: [UUID]

    public init(cards: [UUID], strings: [UUID]) {
        self.cards = cards
        self.strings = strings
    }
}
