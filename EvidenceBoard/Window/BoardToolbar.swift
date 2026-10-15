import SwiftUI
import BoardKit
import CanvasKit

/// The glass toolbar (DESIGN.md §5.1): the tool picker in the middle; new text card, add
/// link, search and theme on the right.
struct BoardToolbar: ToolbarContent {
    let controller: CanvasController

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Tool", selection: Binding(get: { controller.tool }, set: { controller.setTool($0) })) {
                Label("Select (V)", systemImage: "cursorarrow").tag(CanvasTool.select)
                Label("Connect (C)", systemImage: "point.topleft.down.to.point.bottomright.curvepath").tag(CanvasTool.connect)
                Label("Hand (H)", systemImage: "hand.raised").tag(CanvasTool.hand)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Select (V), Connect (C) or Hand (H)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { controller.newTextCard() } label: {
                Label("New Text Card", systemImage: "note.text.badge.plus")
            }
            .help("New Text Card (⇧⌘T)")
            Button { controller.insertLink() } label: {
                Label("Add Link", systemImage: "link.badge.plus")
            }
            .help("Add Link (⌘L)")
            Button {
                if controller.isSearching { controller.endSearch() } else { controller.beginSearch() }
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search (⌘F)")
            Menu {
                Picker("Theme", selection: Binding(get: { controller.theme }, set: { controller.setTheme($0) })) {
                    ForEach(ThemeID.allCases, id: \.self) { id in
                        Text(id.title).tag(id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Theme", systemImage: "circle.lefthalf.filled")
            }
            .help("Theme (⌥⌘T)")
        }
    }
}
