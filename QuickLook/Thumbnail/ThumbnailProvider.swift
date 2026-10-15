import AppKit
import QuickLookThumbnailing
import BoardKit
import CanvasKit

/// Finder icons for `.evboard` files: the board itself, drawn by `BoardRenderer`
/// (DESIGN.md §12.1). Reading the file never touches the network.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let url = request.fileURL
        let maximumSize = request.maximumSize
        let scale = request.scale
        let reply = ReplyBox(handler)
        DispatchQueue.main.async {
            do {
                let board = try BoardCodec.decode(Data(contentsOf: url)).board
                let appearance = CanvasAppearance.forTheme(board.theme, dark: true)
                guard let image = BoardRenderer.image(of: board, appearance: appearance, maxSize: maximumSize, scale: scale) else {
                    reply.send(nil, CocoaError(.fileReadCorruptFile))
                    return
                }
                let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
                let thumbnail = QLThumbnailReply(contextSize: size) { context in
                    context.draw(image, in: CGRect(origin: .zero, size: size))
                    return true
                }
                reply.send(thumbnail, nil)
            } catch {
                reply.send(nil, error)
            }
        }
    }
}

/// Carries Quick Look's completion handler to the main thread, where boards are drawn.
private final class ReplyBox: @unchecked Sendable {
    private let handler: (QLThumbnailReply?, Error?) -> Void

    init(_ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        self.handler = handler
    }

    func send(_ reply: QLThumbnailReply?, _ error: Error?) {
        handler(reply, error)
    }
}
