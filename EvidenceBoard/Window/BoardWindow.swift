import AppKit
import SwiftUI
import BoardKit
import CanvasKit

/// One document window: the canvas edge to edge, with floating glass HUDs on top.
struct BoardWindow: View {
    private let store: BoardStore
    @State private var canvas: CanvasController
    @State private var showsLoadBanner = true
    @AppStorage("alwaysShowMinimap") private var alwaysShowMinimap = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let system = SystemAppearance.shared

    init(store: BoardStore) {
        self.store = store
        _canvas = State(initialValue: CanvasController(store: store))
    }

    private var theme: Theme { Theme.resolve(canvas.theme, systemIsDark: system.isDark) }

    var body: some View {
        BoardCanvas(
            controller: canvas,
            appearance: theme.canvas.adjusted(increaseContrast: contrast == .increased, reduceTransparency: reduceTransparency)
        )
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
            .overlay(alignment: .bottomTrailing) {
                Minimap(controller: canvas, theme: theme, alwaysVisible: alwaysShowMinimap)
                    .padding(16)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if canvas.isSearching {
                        SearchBar(controller: canvas, theme: theme)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
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
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: canvas.isSearching)
            .toolbar { BoardToolbar(controller: canvas) }
            .animation(.easeInOut(duration: 0.2), value: canvas.notice)
            .focusedSceneValue(\.canvasController, canvas)
            #if DEBUG
            .task { await SnapshotScenario.run(on: canvas) }
            #endif
            .onAppear { LaunchTiming.recordFirstFrame() }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .preferredColorScheme(theme.colorScheme)
            .animation(.easeInOut(duration: 0.4), value: theme.id)
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
    static var keep: NSWindow?

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
        case "focus":
            canvas.debugSelectCards(at: [2])
            canvas.focusSelection()
        case "string":
            canvas.debugSelectString(at: 0, zoom: 2.2)
        case "web":
            canvas.addTestWebCards()
            try? await Task.sleep(for: .seconds(2))
            canvas.zoomToFit()
        case "webzoom":
            canvas.addTestWebCards()
            try? await Task.sleep(for: .seconds(2))
            canvas.debugLookAtCards(at: [0, 1], zoom: 1.5)
        case "renderer":
            // What the Quick Look extensions draw, in a window over the board.
            guard let image = canvas.debugRenderBoard(maxSize: CGSize(width: 760, height: 520)) else { break }
            let size = CGSize(width: image.width / 2, height: image.height / 2)
            let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Quick Look rendering"
            let imageView = NSImageView(image: NSImage(cgImage: image, size: size))
            imageView.frame = CGRect(origin: .zero, size: size)
            panel.contentView = imageView
            panel.center()
            panel.isReleasedWhenClosed = false
            panel.orderFrontRegardless()
            SnapshotScenario.keep = panel
        case "search":
            canvas.beginSearch()
            canvas.searchQuery = "night"
        case "minimap":
            UserDefaults.standard.set(true, forKey: "alwaysShowMinimap")
            canvas.zoom(to: 1.6)
        case "hand":
            canvas.setTool(.hand)
        case "cork", "blueprint", "daylight", "noir":
            canvas.setTheme(ThemeID(rawValue: scenario) ?? .system)
        case "webdaylight", "webcork", "webblueprint":
            canvas.setTheme(ThemeID(rawValue: String(scenario.dropFirst(3))) ?? .system)
            canvas.addTestWebCards()
            try? await Task.sleep(for: .seconds(2))
            canvas.zoomToFit()
        case "webzoom2":
            canvas.addTestWebCards()
            try? await Task.sleep(for: .seconds(2))
            canvas.debugLookAtCards(at: [2, 3], zoom: 1.5)
        default:
            break
        }
    }
}
#endif
