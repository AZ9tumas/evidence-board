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
    public private(set) var isEditingText = false
    public private(set) var tool = CanvasTool.select
    /// What the banner over the canvas says while Focus, Trace or the Connect tool is on.
    public private(set) var modeStatus: CanvasModeStatus?
    /// A short message that fades after a moment, such as "these cards aren't connected".
    public private(set) var notice: String?

    @ObservationIgnored
    private var noticeTask: Task<Void, Never>?

    public let store: BoardStore

    @ObservationIgnored
    private weak var view: BoardCanvasView?

    public init(store: BoardStore) {
        self.store = store
        self.zoomPercent = Self.percent(store.viewport.zoom)
        self.isBoardEmpty = store.board.cards.isEmpty
    }

    public var hasSelection: Bool { selectionCount > 0 }
    /// ⌘K and ⌘T work on exactly two cards.
    public var hasCardPair: Bool { selectionCount == 2 }

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

    /// Insert ▸ Image…: picks image or PDF files and pins them to the board.
    public func insertImage() { view?.presentImagePicker() }

    // MARK: Strings

    /// Ties the two selected cards together with a new string.
    public func connectSelection() { view?.connectSelection() }
    /// Highlights the shortest chain of strings between the two selected cards.
    public func traceSelection() { view?.traceSelection() }
    /// Highlights the selection and its neighbors; again to widen by one hop.
    public func focusSelection() { view?.focusSelection() }
    public func toggleConnectTool() { view?.setTool(tool == .connect ? .select : .connect) }

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

    /// Redraws the whole window. On the CI Mac, layer-only changes seem to reach the screen
    /// only when the window redraws, so the snapshot workflow calls this to capture motion.
    public func debugRedrawWindow() {
        view?.window?.display()
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

    func cameraDidChange(_ camera: Camera) {
        store.viewport = camera.viewport
        let percent = Self.percent(camera.zoom)
        if percent != zoomPercent { zoomPercent = percent }
    }

    func boardDidChange(isEmpty: Bool) {
        if isEmpty != isBoardEmpty { isBoardEmpty = isEmpty }
    }

    func selectionDidChange(count: Int, strings: Int) {
        if count != selectionCount { selectionCount = count }
        if strings != stringSelectionCount { stringSelectionCount = strings }
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
