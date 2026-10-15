import SwiftUI
import CanvasKit

/// ⌘F: a glass search field over the top of the board (DESIGN.md §4.6). Matches glow, the
/// rest of the board dims, ↩ moves to the next match and Esc closes it.
struct SearchBar: View {
    @Bindable var controller: CanvasController
    let theme: Theme
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary.color)
            TextField("Search cards, captions and links", text: $controller.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary.color)
                .frame(width: 240)
                .focused($isFocused)
                .onSubmit { controller.nextMatch() }
                .onExitCommand { controller.endSearch() }
            Text(status)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(controller.searchMatchCount == 0 && !isBlank
                    ? Theme.tints[.red]!.from.color
                    : theme.textTertiary.color)
                .fixedSize()
            Divider().frame(height: 14)
            SearchButton(systemImage: "chevron.up", label: "Previous Match", theme: theme) { controller.previousMatch() }
                .disabled(controller.searchMatchCount == 0)
            SearchButton(systemImage: "chevron.down", label: "Next Match", theme: theme) { controller.nextMatch() }
                .disabled(controller.searchMatchCount == 0)
            SearchButton(systemImage: "xmark", label: "Close Search", theme: theme) { controller.endSearch() }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .glassCapsule()
        .onAppear { isFocused = true }
        .onChange(of: controller.isSearching) { _, searching in
            if searching { isFocused = true }
        }
    }

    private var isBlank: Bool {
        controller.searchQuery.allSatisfy(\.isWhitespace)
    }

    private var status: String {
        if isBlank { return "" }
        let count = controller.searchMatchCount
        guard count > 0 else { return "No matches" }
        return "\((controller.searchMatchIndex ?? 0) + 1) of \(count)"
    }
}

private struct SearchButton: View {
    let systemImage: String
    let label: String
    let theme: Theme
    let action: @MainActor () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.textSecondary.color.opacity(isEnabled ? 1 : 0.4))
                .frame(width: 22, height: 20)
                .background(.primary.opacity(isHovered && isEnabled ? 0.08 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
    }
}
