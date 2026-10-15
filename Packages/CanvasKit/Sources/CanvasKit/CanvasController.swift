import AppKit
import Observation
import BoardKit

/// The SwiftUI-facing handle to a canvas: commands in, observable state out.
@MainActor
@Observable
public final class CanvasController {
    /// The zoom as a whole percentage. It only changes when the rounded value does, so the
    /// HUD isn't re-rendered on every frame of a pinch.
    public private(set) var zoomPercent: Int
    public private(set) var isBoardEmpty: Bool
    public private(set) var selectionCount = 0
    public private(set) var stringSelectionCount = 0
    /// How many of the selected cards are web cards.
    public private(set) var linkSelectionCount = 0
    public private(set) var isEditingText = false
    public private(set) var tool = CanvasTool.select
    /// What the banner over the canvas says while Focus, Trace or the Connect tool is on.
    public private(set) var modeStatus: CanvasModeStatus?
    /// A short message that fades after a moment, such as "these cards aren't connected".
    public private(set) var notice: String?
    /// The board's theme, as saved in the file. `.system` follows the Mac's appearance.
    public private(set) var theme: ThemeID

    /// The part of the board in view, in world coordinates.
    public private(set) var visibleWorldRect: CGRect = .zero
    /// True while the view is being panned or zoomed, and for 1.5 s after (the minimap).
    public private(set) var isNavigating = false
    /// Goes up with every edit, so views drawn from the board know to redraw.
    public private(set) var boardRevision = 0

    /// The search field is open.
    public private(set) var isSearching = false
    /// What the search field holds. Setting it searches the board.
    public var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue, isSearching else { return }
            view?.search(searchQuery)
        }
    }
    public private(set) var searchMatchCount = 0
    /// Which match is shown, from 0.
    public private(set) var searchMatchIndex: Int?

    @ObservationIgnored private var lastCameraChange = Date.distantPast
    @ObservationIgnored private var navigationTask: Task<Void, Never>?

    @ObservationIgnored
    private var noticeTask: Task<Void, Never>?

    public let store: BoardStore

    @ObservationIgnored
    private weak var view: BoardCanvasView?

    public init(store: BoardStore) {
        self.store = store
        self.zoomPercent = Self.percent(store.viewport.zoom)
        self.isBoardEmpty = store.board.cards.isEmpty
        self.theme = store.board.theme
    }

    public var hasSelection: Bool { selectionCount > 0 }
    /// ⌘K and ⌘T work on exactly two cards.
    public var hasCardPair: Bool { selectionCount == 2 }
    public var hasLinkSelection: Bool { linkSelectionCount > 0 }

    // MARK: Commands

    public func zoomIn() { view?.zoomIn() }
    public func zoomOut() { view?.zoomOut() }
    public func zoomToFit() { view?.zoomToFit() }
    public func zoom(to level: CGFloat) { view?.zoom(to: level) }

    /// Starts a new text card under the pointer, or in the middle of the view.
    public func newTextCard() {
        guard let view else { return }
        view.createTextCard(at: view.pointerWorldLocation() ?? view.camera.center)
    }

    public func duplicateSelection() { view?.duplicateSelection() }
    public func deleteSelection() { view?.deleteSelection() }
    public func bringSelectionToFront() { view?.reorderSelection(toFront: true) }
    public func sendSelectionToBack() { view?.reorderSelection(toFront: false) }
    public func toggleLockOnSelection() { view?.toggleLockOnSelection() }
    public func addTestCards(count: Int) { view?.addTestCards(count: count) }
    public func addTestPhotos(count: Int) { view?.addTestPhotos(count: count) }
    #if DEBUG
    /// One web card of each layout, plus one still loading, from generated previews.
    public func addTestWebCards() { view?.addTestWebCards() }
    #endif

    /// Insert ▸ Image…: picks image or PDF files and pins them to the board.
    public func insertImage() { view?.presentImagePicker() }

    // MARK: Navigation

    /// Centers the view on `point` (world coordinates), keeping the zoom.
    public func centerView(on point: CGPoint, animated: Bool) {
        guard let view else { return }
        let target = Camera(center: point, zoom: view.camera.zoom)
        if animated {
            view.animateCamera(to: target, anchor: nil)
        } else {
            view.stopCameraAnimation()
            view.setCamera(target)
        }
    }

    // MARK: Search

    /// ⌘F: opens the search field. Typing searches text, captions, link titles and addresses.
    public func beginSearch() {
        guard !isSearching else { return }
        isSearching = true
        if !searchQuery.isEmpty { view?.search(searchQuery) }
    }

    /// Esc: closes the search and brings the board back.
    public func endSearch() {
        guard isSearching else { return }
        isSearching = false
        view?.endSearch()
        searchMatchCount = 0
        searchMatchIndex = nil
    }

    /// ↩ or ⌘G.
    public func nextMatch() { view?.stepSearch(1) }
    /// ⇧⌘G.
    public func previousMatch() { view?.stepSearch(-1) }

    // MARK: Theme

    /// Switches the board to `theme`, as one undoable step.
    public func setTheme(_ theme: ThemeID) { view?.setTheme(theme) }

    /// ⌥⌘T: Automatic, Noir, Cork, Blueprint, Daylight, and around again.
    public func cycleTheme() {
        let all = ThemeID.allCases
        let next = all[((all.firstIndex(of: theme) ?? 0) + 1) % all.count]
        setTheme(next)
    }

    // MARK: Links

    /// Insert ▸ Link…: asks for an address and adds a web card with its preview.
    public func insertLink() { view?.presentLinkPrompt() }
    /// Fetches the selected web cards' previews again.
    public func refreshSelectedPreviews() { view?.refreshPreviews(all: false) }
    public func refreshAllPreviews() { view?.refreshPreviews(all: true) }
    public func openSelectionInBrowser() { view?.openSelectionInBrowser() }
    /// A live look at the selected web card's page, in a popover.
    public func peekSelection() { view?.peekSelection() }
    public func copySelectedLinks() { view?.copySelectedLinks() }

    // MARK: Strings

    /// Ties the two selected cards together with a new string.
    public func connectSelection() { view?.connectSelection() }
    /// Highlights the shortest chain of strings between the two selected cards.
    public func traceSelection() { view?.traceSelection() }
    /// Highlights the selection and its neighbors; again to widen by one hop.
    public func focusSelection() { view?.focusSelection() }
    public func toggleConnectTool() { view?.setTool(tool == .connect ? .select : .connect) }
    /// V, C or H.
    public func setTool(_ newTool: CanvasTool) { view?.setTool(newTool) }

    /// Leaves Focus, Trace and the Connect tool.
    public func exitMode() {
        view?.exitHighlight()
        view?.setTool(.select)
    }

    #if DEBUG
    /// Selects (or starts editing) the card at `index` in file order. Used by the snapshot
    /// workflow, which can't click.
    public func debugSelectCard(at index: Int, edit: Bool) {
        guard let view, store.board.cards.indices.contains(index) else { return }
        let id = store.board.cards[index].id
        if edit {
            view.activate(id, at: nil)
        } else {
            view.select([id])
        }
    }

    /// Starts reframing the photo at `index` and zooms into it, so the faded rest of the image
    /// shows around the card.
    public func debugReframeCard(at index: Int, zoom: CGFloat) {
        guard let view, store.board.cards.indices.contains(index) else { return }
        let card = store.board.cards[index]
        view.beginFraming(card.id)
        view.zoomFraming(by: zoom, around: CGPoint(x: card.frame.midX, y: card.frame.midY))
    }

    /// Selects the cards at `indices`, in file order.
    public func debugSelectCards(at indices: [Int]) {
        guard let view else { return }
        view.select(Set(indices.filter(store.board.cards.indices.contains).map { store.board.cards[$0].id }))
    }

    /// Pulls a string out of one card's pin and holds it over another card, mid-gesture.
    public func debugBeginConnecting(from source: Int, toward target: Int) {
        guard let view, store.board.cards.indices.contains(source), store.board.cards.indices.contains(target) else { return }
        let card = store.board.cards[target]
        view.beginConnecting(from: store.board.cards[source].id)
        view.continueConnecting(to: CGPoint(x: card.frame.midX - 30, y: card.frame.y + 40))
    }

    /// Centers the view on the cards at `indices` (file order) at `zoom`.
    public func debugLookAtCards(at indices: [Int], zoom: CGFloat) {
        guard let view else { return }
        let cards = indices.filter(store.board.cards.indices.contains).map { store.board.cards[$0] }
        guard let bounds = CanvasGeometry.contentBounds(of: cards) else { return }
        view.setCamera(Camera(center: CGPoint(x: bounds.midX, y: bounds.midY), zoom: zoom))
    }

    /// Selects the string at `index` and zooms in on its middle.
    public func debugSelectString(at index: Int, zoom: CGFloat) {
        guard let view, store.board.strings.indices.contains(index) else { return }
        let id = store.board.strings[index].id
        view.select([], strings: [id])
        guard let node = view.stringNodes[id] else { return }
        view.setCamera(Camera(center: node.curve.point(at: 0.5), zoom: zoom))
    }
    #endif

    // MARK: Canvas callbacks

    func attach(_ view: BoardCanvasView) {
        self.view = view
        view.controller = self
    }

    func cameraDidChange(_ camera: Camera, visible: CGRect) {
        store.viewport = camera.viewport
        visibleWorldRect = visible
        noteNavigation()
        let percent = Self.percent(camera.zoom)
        if percent != zoomPercent { zoomPercent = percent }
    }

    func boardDidChange(isEmpty: Bool) {
        boardRevision += 1
        if isEmpty != isBoardEmpty { isBoardEmpty = isEmpty }
    }

    func selectionDidChange(count: Int, strings: Int, links: Int) {
        if count != selectionCount { selectionCount = count }
        if strings != stringSelectionCount { stringSelectionCount = strings }
        if links != linkSelectionCount { linkSelectionCount = links }
    }

    func searchDidUpdate(count: Int, index: Int?) {
        if count != searchMatchCount { searchMatchCount = count }
        if index != searchMatchIndex { searchMatchIndex = index }
    }

    /// The board left search mode by itself (Esc on the board, Focus or Trace).
    func searchDidEnd() {
        guard isSearching else { return }
        isSearching = false
        searchMatchCount = 0
        searchMatchIndex = nil
    }

    /// Shows the minimap while the camera moves and hides it 1.5 s after it stops.
    private func noteNavigation() {
        lastCameraChange = .now
        if !isNavigating { isNavigating = true }
        guard navigationTask == nil else { return }
        navigationTask = Task { @MainActor [weak self] in
            while let wait = self.map({ $0.lastCameraChange.addingTimeInterval(1.5).timeIntervalSinceNow }), wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            self?.isNavigating = false
            self?.navigationTask = nil
        }
    }

    func themeDidChange(_ newTheme: ThemeID) {
        if newTheme != theme { theme = newTheme }
    }

    func toolDidChange(_ newTool: CanvasTool) {
        if newTool != tool { tool = newTool }
    }

    func modeDidChange(_ status: CanvasModeStatus?) {
        if status != modeStatus { modeStatus = status }
    }

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func editingDidChange(_ editing: Bool) {
        if editing != isEditingText { isEditingText = editing }
    }

    private static func percent(_ zoom: Double) -> Int {
        Int((zoom * 100).rounded())
    }
}
