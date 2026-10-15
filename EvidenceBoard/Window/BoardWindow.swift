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
                if canvas.isBoardEmpty {
                    EmptyBoardHint(theme: theme)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                ZoomHUD(controller: canvas, theme: theme)
                    .padding(16)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if showsLoadBanner, let summary = store.loadReport.summary {
                        LoadBanner(message: summary, theme: theme) { showsLoadBanner = false }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let status = canvas.modeStatus {
                        ModeBanner(status: status, theme: theme) { canvas.exitMode() }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let notice = canvas.notice {
                        NoticeBanner(message: notice, theme: theme)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 12)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showsLoadBanner)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: canvas.modeStatus)
            .animation(.easeInOut(duration: 0.2), value: canvas.notice)
            .focusedSceneValue(\.canvasController, canvas)
            #if DEBUG
            .task { await SnapshotScenario.run(on: canvas) }
            #endif
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
            Text("Double-click or press T to add a text card")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary.color)
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

/// Shows which mode the canvas is in, how to go further and how to leave.
private struct ModeBanner: View {
    let status: CanvasModeStatus
    let theme: Theme
    let exit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.accentString.linear())
            Text(status.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary.color)
            Text(status.hint)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary.color)
            Button(action: exit) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassCapsule()
    }
}

/// A short message that fades on its own.
private struct NoticeBanner: View {
    let message: String
    let theme: Theme

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCapsule()
            .allowsHitTesting(false)
    }
}

#if DEBUG
/// Puts the window into a known state for the snapshot workflow, chosen with the
/// `EB_SNAPSHOT_SCENARIO` environment variable. Debug builds only.
@MainActor
private enum SnapshotScenario {
    static func run(on canvas: CanvasController) async {
        guard let scenario = ProcessInfo.processInfo.environment["EB_SNAPSHOT_SCENARIO"] else { return }
        try? await Task.sleep(for: .seconds(1))
        switch scenario {
        case "select":
            canvas.debugSelectCard(at: 1, edit: false)
        case "edit":
            canvas.debugSelectCard(at: 1, edit: true)
        case "stress":
            canvas.addTestCards(count: 500)
            try? await Task.sleep(for: .milliseconds(300))
            canvas.zoomToFit()
        case "photos":
            canvas.addTestPhotos(count: 12)
            try? await Task.sleep(for: .seconds(2))
            canvas.zoomToFit()
        case "photos200":
            canvas.addTestPhotos(count: 200)
            try? await Task.sleep(for: .seconds(4))
            canvas.zoomToFit()
        case "caption":
            canvas.debugSelectCard(at: 2, edit: true)
        case "reframe":
            canvas.debugReframeCard(at: 2, zoom: 1.8)
        case "connect":
            canvas.debugBeginConnecting(from: 0, toward: 4)
        case "trace":
            canvas.debugSelectCards(at: [1, 4])
            canvas.traceSelection()
        case "tracepath":
            canvas.debugSelectCards(at: [1, 4])
            canvas.traceSelection()
            canvas.debugShowWholePulse()
        case "focus":
            canvas.debugSelectCards(at: [2])
            canvas.focusSelection()
        case "string":
            canvas.debugSelectString(at: 0, zoom: 2.2)
        default:
            break
        }
    }
}
#endif
