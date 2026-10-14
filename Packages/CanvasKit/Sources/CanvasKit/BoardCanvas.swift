import SwiftUI

/// Hosts the board canvas in SwiftUI.
public struct BoardCanvas: NSViewRepresentable {
    private let controller: CanvasController
    private let appearance: CanvasAppearance

    public init(controller: CanvasController, appearance: CanvasAppearance) {
        self.controller = controller
        self.appearance = appearance
    }

    public func makeNSView(context: Context) -> BoardCanvasHostView {
        let canvas = BoardCanvasView(store: controller.store, appearance: appearance)
        controller.attach(canvas)
        return BoardCanvasHostView(canvas: canvas)
    }

    public func updateNSView(_ host: BoardCanvasHostView, context: Context) {
        host.canvas.canvasAppearance = appearance
        // Edits register with the document's undo manager, which is also how the document
        // learns that it has unsaved changes.
        host.canvas.boardEditor.undoManager = context.environment.undoManager ?? host.window?.undoManager
    }
}

/// Holds the layer-hosting canvas plus the views that float over it, such as the text editor.
/// (A layer-hosting view can't have subviews of its own.)
public final class BoardCanvasHostView: NSView {
    public let canvas: BoardCanvasView

    init(canvas: BoardCanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        wantsLayer = true
        canvas.autoresizingMask = [.width, .height]
        canvas.frame = bounds
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BoardCanvasHostView is created in code")
    }

    public override var isFlipped: Bool { true }
}
