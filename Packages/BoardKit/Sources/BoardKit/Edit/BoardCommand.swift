import Foundation

/// One change to a board. Every edit goes through ``BoardStore/apply(_:)``, which returns the
/// command that reverses it, so undo and redo come for free.
public enum BoardCommand: Sendable, Equatable {
    /// Adds cards. With `positions`, card `i` goes to array index `positions[i]`; the indices
    /// must be ascending. That's how a removal is undone without reordering the file.
    case insertCards([Card], positions: [Int]? = nil)
    /// Removes cards and every string attached to them.
    case removeCards(Set<UUID>)
    /// Adds strings whose two cards both exist.
    case insertStrings([BoardString], positions: [Int]? = nil)
    case removeStrings(Set<UUID>)
    /// Replaces strings by ID: color, label, sag, direction and so on. A string that would
    /// end up tied to a missing card, or to the same card at both ends, is left as it was.
    case updateStrings([BoardString])
    /// Moves or resizes cards.
    case setFrames([UUID: Rect])
    /// Replaces cards by ID: text, style, tint, z, lock and so on. Unknown IDs are ignored.
    case updateCards([Card])
    /// Adds assets that aren't on the board yet.
    case addAssets([AssetID: Asset])
    case removeAssets(Set<AssetID>)
    /// Changes the board's theme.
    case setTheme(ThemeID)
    /// Several commands applied in order, undone in reverse.
    case batch([BoardCommand])
}

/// What a command changed, so views can update just those items.
public struct BoardChanges: Sendable, Equatable {
    public var insertedCards: Set<UUID> = []
    public var updatedCards: Set<UUID> = []
    public var removedCards: Set<UUID> = []
    public var insertedStrings: Set<UUID> = []
    public var updatedStrings: Set<UUID> = []
    public var removedStrings: Set<UUID> = []
    public var assetsChanged = false
    public var themeChanged = false

    public init() {}

    public var isEmpty: Bool {
        insertedCards.isEmpty && updatedCards.isEmpty && removedCards.isEmpty
            && insertedStrings.isEmpty && updatedStrings.isEmpty && removedStrings.isEmpty && !assetsChanged
            && !themeChanged
    }
}
