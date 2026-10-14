import SwiftUI

/// Hosts a ``BoardCanvasView`` in SwiftUI.
public struct BoardCanvas: NSViewRepresentable {
    private let controller: CanvasController
    private let appearance: CanvasAppearance

    public init(controller: CanvasController, appearance: CanvasAppearance) {
        self.controller = controller
        self.appearance = appearance
    }

    public func makeNSView(context: Context) -> BoardCanvasView {
        let view = BoardCanvasView(store: controller.store, appearance: appearance)
        controller.attach(view)
        return view
    }

    public func updateNSView(_ view: BoardCanvasView, context: Context) {
        view.canvasAppearance = appearance
    }
}
