import SwiftUI
import BoardKit
import CanvasKit

/// Menu bar commands for the focused board window. Cut, Copy, Paste, Delete and Select All
/// come from the standard Edit menu and reach the canvas through the responder chain.
struct BoardCommands: Commands {
    @FocusedValue(\.canvasController) private var canvas
    @AppStorage("alwaysShowMinimap") private var alwaysShowMinimap = false

    private var hasSelection: Bool { canvas?.hasSelection ?? false }
    private var hasLinkSelection: Bool { canvas?.hasLinkSelection ?? false }

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Duplicate") { canvas?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!hasSelection)
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") { canvas?.beginSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(canvas == nil)
            Button("Find Next") { canvas?.nextMatch() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!(canvas?.isSearching ?? false))
            Button("Find Previous") { canvas?.previousMatch() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!(canvas?.isSearching ?? false))
        }

        CommandMenu("Insert") {
            Button("Text Card") { canvas?.newTextCard() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(canvas == nil)
            Button("Image…") { canvas?.insertImage() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(canvas == nil)
            Button("Link…") { canvas?.insertLink() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(canvas == nil)
        }

        CommandMenu("Board") {
            Button("Refresh Preview") { canvas?.refreshSelectedPreviews() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!hasLinkSelection)
            Button("Refresh All Previews") { canvas?.refreshAllPreviews() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(canvas == nil)
            Divider()
            // ⌘↩ is handled by the canvas, so it doesn't reach the text editor's own ⌘↩.
            Button("Open in Browser (⌘↩)") { canvas?.openSelectionInBrowser() }
                .disabled(!hasLinkSelection)
            Button("Peek (Space)") { canvas?.peekSelection() }
                .disabled(canvas?.linkSelectionCount != 1 || canvas?.selectionCount != 1)
            Button("Copy Link") { canvas?.copySelectedLinks() }
                .disabled(!hasLinkSelection)
            Divider()
            Picker("Theme", selection: Binding(
                get: { canvas?.theme ?? .system },
                set: { canvas?.setTheme($0) }
            )) {
                ForEach(ThemeID.allCases, id: \.self) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .disabled(canvas == nil)
            Button("Next Theme") { canvas?.cycleTheme() }
                .keyboardShortcut("t", modifiers: [.command, .option])
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
            Toggle("Always Show Minimap", isOn: $alwaysShowMinimap)
            Divider()
        }

        #if DEBUG
        CommandMenu("Debug") {
            Button("Add 100 Test Cards") { canvas?.addTestCards(count: 100) }
            Button("Add 500 Test Cards") { canvas?.addTestCards(count: 500) }
            Divider()
            Button("Add 50 Test Photos") { canvas?.addTestPhotos(count: 50) }
            Button("Add 200 Test Photos") { canvas?.addTestPhotos(count: 200) }
            Divider()
            Button("Add Test Links") { canvas?.addTestWebCards() }
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
