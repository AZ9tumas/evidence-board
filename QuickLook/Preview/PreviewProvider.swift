import AppKit
import QuickLookUI
import UniformTypeIdentifiers
import BoardKit
import CanvasKit

/// Space-bar previews of `.evboard` files in Finder: the whole board as a picture, drawn by
/// `BoardRenderer` (DESIGN.md §12.1). Reading the file never touches the network.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    static let maximumSize = CGSize(width: 1600, height: 1000)

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL)
        let board = try BoardCodec.decode(data).board
        let rendered = await MainActor.run { () -> (png: Data, size: CGSize)? in
            let appearance = CanvasAppearance.forTheme(board.theme, dark: true)
            guard let image = BoardRenderer.image(of: board, appearance: appearance, maxSize: Self.maximumSize, scale: 2),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
            return (png, CGSize(width: image.width / 2, height: image.height / 2))
        }
        guard let rendered else { throw CocoaError(.fileReadCorruptFile) }
        let reply = QLPreviewReply(dataOfContentType: .png, contentSize: rendered.size) { _ in rendered.png }
        reply.title = board.title
        return reply
    }
}
