import Foundation
import BoardKit

/// Applies board commands and registers their inverses with the document's undo manager.
///
/// Registering undo is also what tells a SwiftUI document that it has unsaved changes.
@MainActor
final class BoardEditor {
    let store: BoardStore
    weak var undoManager: UndoManager?

    init(store: BoardStore) {
        self.store = store
    }

    /// Applies `command` as one undoable step named `actionName` (shown as "Undo Move").
    func perform(_ command: BoardCommand, actionName: String) {
        guard let inverse = store.apply(command) else { return }
        registerUndo(of: inverse, actionName: actionName)
    }

    /// Records `inverse` for an edit that was already applied, for example a text card that
    /// existed while it was being typed but only becomes a real edit when typing ends.
    func registerUndo(of inverse: BoardCommand, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                editor.perform(inverse, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }
}
