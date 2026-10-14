import SwiftUI
import BoardKit
import CanvasKit

/// One document window: the canvas edge to edge, with floating glass HUDs on top.
struct BoardWindow: View {
    private let store: BoardStore
    private let theme: Theme
    @State private var canvas: CanvasController
    @State private var showsLoadBanner = true

    init(store: BoardStore) {
        self.store = store
        self.theme = Theme.resolve(store.board.theme)
        _canvas = State(initialValue: CanvasController(store: store))
    }

    var body: some View {
        BoardCanvas(controller: canvas, appearance: theme.canvas)
            .ignoresSafeArea()
            .overlay {
                if store.board.cards.isEmpty {
                    EmptyBoardHint(theme: theme)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                ZoomHUD(controller: canvas, theme: theme)
                    .padding(16)
            }
            .overlay(alignment: .top) {
                if showsLoadBanner, let summary = store.loadReport.summary {
                    LoadBanner(message: summary, theme: theme) { showsLoadBanner = false }
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showsLoadBanner)
            .focusedSceneValue(\.canvasController, canvas)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .preferredColorScheme(.dark)
            .frame(minWidth: 640, minHeight: 420)
    }
}

/// Shown in the middle of a board with no cards yet.
private struct EmptyBoardHint: View {
    let theme: Theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(theme.accentString.linear())
                .rotationEffect(.degrees(-24))
                .shadow(color: theme.accentString.from.color.opacity(0.45), radius: 12)
            Text("An empty board")
                .font(.system(size: 22, weight: .semibold))
                .kerning(-0.3)
                .foregroundStyle(theme.textPrimary.color)
            Text("Pinch or ⌘-scroll to zoom · Scroll to pan · Hold Space and drag to move around")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary.color)
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }
}

/// A non-blocking note when part of a file couldn't be loaded.
private struct LoadBanner: View {
    let message: String
    let theme: Theme
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.tints[.amber]!.linear())
            Text(message)
                .foregroundStyle(theme.textPrimary.color)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassCapsule()
    }
}
