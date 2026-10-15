import SwiftUI
import CanvasKit

@main
struct EvidenceBoardApp: App {
    init() {
        LaunchTiming.mark("app code starts")
        CanvasLaunchMarks.mark = LaunchTiming.isTiming ? { LaunchTiming.mark($0) } : nil
    }

    var body: some Scene {
        DocumentGroup(newDocument: { BoardDocument() }) { file in
            BoardWindow(store: file.document.store)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { BoardCommands() }
    }
}
