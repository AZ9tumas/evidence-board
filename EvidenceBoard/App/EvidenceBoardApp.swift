import SwiftUI

@main
struct EvidenceBoardApp: App {
    init() {
        LaunchTiming.mark("app code starts")
    }

    var body: some Scene {
        DocumentGroup(newDocument: { BoardDocument() }) { file in
            BoardWindow(store: file.document.store)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { BoardCommands() }
    }
}
