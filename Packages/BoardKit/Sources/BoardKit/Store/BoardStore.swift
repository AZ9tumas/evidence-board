import Foundation

/// The live board behind one document window.
///
/// M0 only reads the board and tracks the camera. Undoable edit commands and change sets for
/// the canvas arrive with M1.
@MainActor
public final class BoardStore {
    public private(set) var board: Board
    public let loadReport: LoadReport

    /// The current camera position. Kept apart from ``board`` so panning never marks the
    /// document as edited, and merged back in when the document is saved.
    public var viewport: Viewport

    nonisolated public init(board: Board, loadReport: LoadReport = LoadReport()) {
        self.board = board
        self.loadReport = loadReport
        self.viewport = board.viewport
    }

    /// The board as it should be written to disk right now.
    public func snapshot() -> Board {
        var board = board
        board.viewport = viewport
        return board
    }
}
