import CoreGraphics
import Observation
import BoardKit

/// The SwiftUI-facing handle to a canvas: zoom commands in, zoom level out.
@MainActor
@Observable
public final class CanvasController {
    /// The zoom as a whole percentage. It only changes when the rounded value does, so the
    /// HUD isn't re-rendered on every frame of a pinch.
    public private(set) var zoomPercent: Int

    public let store: BoardStore

    @ObservationIgnored
    private weak var view: BoardCanvasView?

    public init(store: BoardStore) {
        self.store = store
        self.zoomPercent = Self.percent(store.viewport.zoom)
    }

    public func zoomIn() { view?.zoomIn() }
    public func zoomOut() { view?.zoomOut() }
    public func zoomToFit() { view?.zoomToFit() }
    public func zoom(to level: CGFloat) { view?.zoom(to: level) }

    func attach(_ view: BoardCanvasView) {
        self.view = view
        view.controller = self
    }

    func cameraDidChange(_ camera: Camera) {
        store.viewport = camera.viewport
        let percent = Self.percent(camera.zoom)
        if percent != zoomPercent { zoomPercent = percent }
    }

    private static func percent(_ zoom: Double) -> Int {
        Int((zoom * 100).rounded())
    }
}
