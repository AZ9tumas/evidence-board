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
    public private(set) var isEditingText = false

    public let store: BoardStore

    @ObservationIgnored
    private weak var view: BoardCanvasView?

    public init(store: BoardStore) {
        self.store = store
        self.zoomPercent = Self.percent(store.viewport.zoom)
        self.isBoardEmpty = store.board.cards.isEmpty
    }

    public var hasSelection: Bool { selectionCount > 0 }

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

    func selectionDidChange(count: Int) {
        if count != selectionCount { selectionCount = count }
    }

    func editingDidChange(_ editing: Bool) {
        if editing != isEditingText { isEditingText = editing }
    }

    private static func percent(_ zoom: Double) -> Int {
        Int((zoom * 100).rounded())
    }
}
