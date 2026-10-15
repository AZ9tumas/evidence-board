import SwiftUI

/// Steps of the app's launch inside the canvas, for the launch budget (DESIGN.md §11). The
/// app points this at its launch timer; nil otherwise.
public enum CanvasLaunchMarks {
    nonisolated(unsafe) public static var mark: (@Sendable (String) -> Void)?
}

/// Hosts the board canvas in SwiftUI.
public struct BoardCanvas: NSViewRepresentable {
    private let controller: CanvasController
    private let appearance: CanvasAppearance

    public init(controller: CanvasController, appearance: CanvasAppearance) {
        self.controller = controller
        self.appearance = appearance
    }

    public func makeNSView(context: Context) -> BoardCanvasHostView {
        CanvasLaunchMarks.mark?("canvas: making view")
        let canvas = BoardCanvasView(store: controller.store, appearance: appearance)
        controller.attach(canvas)
        CanvasLaunchMarks.mark?("canvas: view made")
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
