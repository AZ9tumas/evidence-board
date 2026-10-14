import SwiftUI
import CanvasKit

/// Menu bar commands for the focused board window.
struct BoardCommands: Commands {
    @FocusedValue(\.canvasController) private var canvas

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Zoom In") { canvas?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { canvas?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Zoom to Fit") { canvas?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Actual Size") { canvas?.zoom(to: 1) }
                .keyboardShortcut("1", modifiers: .command)
            Divider()
        }
    }
}

struct CanvasControllerFocusKey: FocusedValueKey {
    typealias Value = CanvasController
}

extension FocusedValues {
    var canvasController: CanvasController? {
        get { self[CanvasControllerFocusKey.self] }
        set { self[CanvasControllerFocusKey.self] = newValue }
    }
}
