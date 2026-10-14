import SwiftUI

@main
struct EvidenceBoardApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { BoardDocument() }) { file in
            BoardWindow(store: file.document.store)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { BoardCommands() }
    }
}
