import SwiftUI
import CanvasKit

/// Menu bar commands for the focused board window. Cut, Copy, Paste, Delete and Select All
/// come from the standard Edit menu and reach the canvas through the responder chain.
struct BoardCommands: Commands {
    @FocusedValue(\.canvasController) private var canvas

    private var hasSelection: Bool { canvas?.hasSelection ?? false }

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Duplicate") { canvas?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!hasSelection)
        }

        CommandMenu("Insert") {
            Button("Text Card") { canvas?.newTextCard() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(canvas == nil)
        }

        CommandMenu("Arrange") {
            Button("Bring to Front") { canvas?.bringSelectionToFront() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(!hasSelection)
            Button("Send to Back") { canvas?.sendSelectionToBack() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(!hasSelection)
            Divider()
            Button("Lock or Unlock") { canvas?.toggleLockOnSelection() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!hasSelection)
        }

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

        #if DEBUG
        CommandMenu("Debug") {
            Button("Add 100 Test Cards") { canvas?.addTestCards(count: 100) }
            Button("Add 500 Test Cards") { canvas?.addTestCards(count: 500) }
        }
        #endif
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
