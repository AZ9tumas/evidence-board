import SwiftUI
import UniformTypeIdentifiers
import BoardKit

extension UTType {
    /// `.evboard`: plain JSON, declared in Info.plist.
    static let evidenceBoard = UTType(exportedAs: "com.evidenceboard.board", conformingTo: .json)
}

/// One open board. Decoding happens on open, encoding runs on SwiftUI's background writer
/// thread from a value snapshot, so saving never blocks the canvas.
final class BoardDocument: ReferenceFileDocument, Sendable {
    typealias Snapshot = Board

    nonisolated static let readableContentTypes: [UTType] = [.evidenceBoard, .json]
    nonisolated static let writableContentTypes: [UTType] = [.evidenceBoard]

    let store: BoardStore

    nonisolated init() {
        store = BoardStore(board: .new())
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let result = try BoardCodec.decode(data)
        store = BoardStore(board: result.board, loadReport: result.report)
    }

    nonisolated func snapshot(contentType: UTType) throws -> Board {
        // SwiftUI may ask from a background thread; the store's snapshot is thread-safe.
        store.snapshot()
    }

    nonisolated func fileWrapper(snapshot: Board, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BoardCodec.encode(snapshot))
    }
}
