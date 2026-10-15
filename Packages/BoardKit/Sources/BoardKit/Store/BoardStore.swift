import Foundation
import Synchronization

/// The live board behind one document window.
///
/// All edits go through ``apply(_:)``. It mutates the board, tells observers exactly which
/// cards and strings changed, and returns the inverse command for the undo stack.
///
/// The store lives on the main actor, but saving doesn't: SwiftUI asks for document
/// snapshots on a background thread. So every change is also copied into a lock-protected
/// mirror that ``snapshot(now:)`` reads from any thread. Copying a `Board` is cheap because
/// its arrays are copy-on-write.
@MainActor
public final class BoardStore {
    public typealias Observer = @MainActor @Sendable (BoardChanges) -> Void

    public private(set) var board: Board
    public let loadReport: LoadReport

    /// The current camera position. Kept apart from ``board`` so panning never marks the
    /// document as edited, and merged back in when the document is saved.
    public var viewport: Viewport {
        didSet { mirror.withLock { $0.viewport = viewport } }
    }

    /// Increases with every change. Saving compares it to stamp `modifiedAt`.
    public private(set) var revision = 0

    private var cardIndex: [UUID: Int]
    private var stringIndex: [UUID: Int]
    private var observers: [UUID: Observer] = [:]
    private var cachedGraph: BoardGraph?

    private struct Mirror {
        var board: Board
        var viewport: Viewport
        var revision = 0
        var stampedRevision = 0
        var modifiedAt: Date
    }

    private let mirror: Mutex<Mirror>

    nonisolated public init(board: Board, loadReport: LoadReport = LoadReport()) {
        self.board = board
        self.loadReport = loadReport
        self.viewport = board.viewport
        self.cardIndex = Self.makeIndex(board.cards)
        self.stringIndex = Self.makeIndex(board.strings)
        self.mirror = Mutex(Mirror(board: board, viewport: board.viewport, modifiedAt: board.modifiedAt))
    }

    /// The board as it should be written to disk right now. Safe to call from any thread.
    /// `modifiedAt` is stamped with `now` the first time a snapshot follows a change.
    nonisolated public func snapshot(now: Date = .now) -> Board {
        mirror.withLock { mirror in
            if mirror.revision != mirror.stampedRevision {
                mirror.modifiedAt = now.truncatedToSeconds
                mirror.stampedRevision = mirror.revision
            }
            var board = mirror.board
            board.viewport = mirror.viewport
            board.modifiedAt = mirror.modifiedAt
            return board
        }
    }

    // MARK: Lookup

    public func card(_ id: UUID) -> Card? {
        cardIndex[id].map { board.cards[$0] }
    }

    public func contains(card id: UUID) -> Bool {
        cardIndex[id] != nil
    }

    public func string(_ id: UUID) -> BoardString? {
        stringIndex[id].map { board.strings[$0] }
    }

    /// The board's strings as a graph, for Focus and Trace. Built on first use after a change.
    public var graph: BoardGraph {
        if let cachedGraph { return cachedGraph }
        let graph = BoardGraph(strings: board.strings)
        cachedGraph = graph
        return graph
    }

    /// The highest `z` on the board, or 0 when it's empty.
    public var maxZ: Int { board.cards.map(\.z).max() ?? 0 }
    public var minZ: Int { board.cards.map(\.z).min() ?? 0 }

    // MARK: Observing

    @discardableResult
    public func addObserver(_ observer: @escaping Observer) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    // MARK: Editing

    /// Applies `command` and returns the command that undoes it, or `nil` if nothing changed.
    @discardableResult
    public func apply(_ command: BoardCommand) -> BoardCommand? {
        var changes = BoardChanges()
        let inverse = perform(command, changes: &changes)
        guard !changes.isEmpty else { return nil }
        if !changes.insertedStrings.isEmpty || !changes.removedStrings.isEmpty || !changes.updatedStrings.isEmpty {
            stringIndex = Self.makeIndex(board.strings)
            cachedGraph = nil
        }
        revision += 1
        let board = board
        let revision = revision
        mirror.withLock {
            $0.board = board
            $0.revision = revision
        }
        for observer in observers.values { observer(changes) }
        return inverse
    }

    private func perform(_ command: BoardCommand, changes: inout BoardChanges) -> BoardCommand {
        switch command {
        case .insertCards(let cards, let positions):
            var inserted: [UUID] = []
            var seen = Set<UUID>()
            for (offset, card) in cards.enumerated() where cardIndex[card.id] == nil && seen.insert(card.id).inserted {
                let position = positions.flatMap { $0.indices.contains(offset) ? $0[offset] : nil }
                board.cards.insert(card, at: min(max(position ?? board.cards.count, 0), board.cards.count))
                inserted.append(card.id)
            }
            guard !inserted.isEmpty else { return .batch([]) }
            cardIndex = Self.makeIndex(board.cards)
            changes.insertedCards.formUnion(inserted)
            return .removeCards(Set(inserted))

        case .removeCards(let ids):
            let removed = board.cards.enumerated().filter { ids.contains($0.element.id) }
            guard !removed.isEmpty else { return .batch([]) }
            let removedIDs = Set(removed.map { $0.element.id })
            let detached = board.strings.enumerated().filter {
                removedIDs.contains($0.element.from) || removedIDs.contains($0.element.to)
            }
            board.cards.removeAll { removedIDs.contains($0.id) }
            board.strings.removeAll { removedIDs.contains($0.from) || removedIDs.contains($0.to) }
            cardIndex = Self.makeIndex(board.cards)
            changes.removedCards.formUnion(removedIDs)
            changes.removedStrings.formUnion(detached.map { $0.element.id })
            var inverse: [BoardCommand] = [.insertCards(removed.map { $0.element }, positions: removed.map { $0.offset })]
            if !detached.isEmpty {
                inverse.append(.insertStrings(detached.map { $0.element }, positions: detached.map { $0.offset }))
            }
            return .batch(inverse)

        case .insertStrings(let strings, let positions):
            var existing = Set(board.strings.map(\.id))
            var inserted: [UUID] = []
            for (offset, string) in strings.enumerated() {
                guard string.from != string.to,
                      cardIndex[string.from] != nil, cardIndex[string.to] != nil,
                      existing.insert(string.id).inserted else { continue }
                let position = positions.flatMap { $0.indices.contains(offset) ? $0[offset] : nil }
                board.strings.insert(string, at: min(max(position ?? board.strings.count, 0), board.strings.count))
                inserted.append(string.id)
            }
            guard !inserted.isEmpty else { return .batch([]) }
            changes.insertedStrings.formUnion(inserted)
            return .removeStrings(Set(inserted))

        case .removeStrings(let ids):
            let removed = board.strings.enumerated().filter { ids.contains($0.element.id) }
            guard !removed.isEmpty else { return .batch([]) }
            board.strings.removeAll { ids.contains($0.id) }
            changes.removedStrings.formUnion(removed.map { $0.element.id })
            return .insertStrings(removed.map { $0.element }, positions: removed.map { $0.offset })

        case .updateStrings(let strings):
            let positions = Self.makeIndex(board.strings)
            var previous: [BoardString] = []
            for string in strings {
                guard let index = positions[string.id], board.strings[index] != string,
                      string.from != string.to, cardIndex[string.from] != nil, cardIndex[string.to] != nil else { continue }
                previous.append(board.strings[index])
                board.strings[index] = string
            }
            guard !previous.isEmpty else { return .batch([]) }
            changes.updatedStrings.formUnion(previous.map(\.id))
            return .updateStrings(previous)

        case .setFrames(let frames):
            var previous: [UUID: Rect] = [:]
            for (id, frame) in frames {
                guard let index = cardIndex[id], board.cards[index].frame != frame else { continue }
                previous[id] = board.cards[index].frame
                board.cards[index].frame = frame
            }
            guard !previous.isEmpty else { return .batch([]) }
            changes.updatedCards.formUnion(previous.keys)
            return .setFrames(previous)

        case .updateCards(let cards):
            var previous: [Card] = []
            for card in cards {
                guard let index = cardIndex[card.id], board.cards[index] != card else { continue }
                previous.append(board.cards[index])
                board.cards[index] = card
            }
            guard !previous.isEmpty else { return .batch([]) }
            changes.updatedCards.formUnion(previous.map(\.id))
            return .updateCards(previous)

        case .addAssets(let assets):
            let added = assets.filter { board.assets[$0.key] == nil }
            guard !added.isEmpty else { return .batch([]) }
            board.assets.merge(added) { current, _ in current }
            changes.assetsChanged = true
            return .removeAssets(Set(added.keys))

        case .removeAssets(let ids):
            let removed = board.assets.filter { ids.contains($0.key) }
            guard !removed.isEmpty else { return .batch([]) }
            for id in removed.keys { board.assets[id] = nil }
            changes.assetsChanged = true
            return .addAssets(removed)

        case .setTheme(let theme):
            guard board.theme != theme else { return .batch([]) }
            let previous = board.theme
            board.theme = theme
            changes.themeChanged = true
            return .setTheme(previous)

        case .batch(let commands):
            let inverses = commands.map { perform($0, changes: &changes) }
            return .batch(inverses.reversed())
        }
    }

    private nonisolated static func makeIndex<Item: Identifiable>(_ items: [Item]) -> [UUID: Int] where Item.ID == UUID {
        Dictionary(items.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
}
