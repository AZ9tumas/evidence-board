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
            Button("Image…") { canvas?.insertImage() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
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

        CommandMenu("Strings") {
            Button("Connect Selected Cards") { canvas?.connectSelection() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!(canvas?.hasCardPair ?? false))
            Button(canvas?.tool == .connect ? "Stop Connecting (C)" : "Connect Tool (C)") { canvas?.toggleConnectTool() }
                .disabled(canvas == nil)
            Divider()
            Button("Trace Path") { canvas?.traceSelection() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!(canvas?.hasCardPair ?? false))
            Button("Focus on Selection (F)") { canvas?.focusSelection() }
                .disabled(!hasSelection)
            Button("Exit Focus or Trace (Esc)") { canvas?.exitMode() }
                .disabled(canvas?.modeStatus == nil)
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
            Divider()
            Button("Add 50 Test Photos") { canvas?.addTestPhotos(count: 50) }
            Button("Add 200 Test Photos") { canvas?.addTestPhotos(count: 200) }
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
