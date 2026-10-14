import CoreGraphics
import Foundation
import Testing
@testable import CanvasKit

@Suite("Camera")
struct CameraTests {
    let size = CGSize(width: 1200, height: 800)

    @Test func viewCenterShowsCameraCenter() {
        let camera = Camera(center: CGPoint(x: 300, y: -40), zoom: 2)
        #expect(camera.worldToView(camera.center, in: size) == CGPoint(x: 600, y: 400))
    }

    @Test(arguments: [0.05, 0.5, 1, 3.7, 8])
    func conversionsAreInverse(zoom: CGFloat) {
        let camera = Camera(center: CGPoint(x: -812.5, y: 140), zoom: zoom)
        let world = CGPoint(x: 123.25, y: -987.5)
        let roundTrip = camera.viewToWorld(camera.worldToView(world, in: size), in: size)
        #expect(roundTrip.isClose(to: world))
    }

    @Test func transformMatchesWorldToView() {
        let camera = Camera(center: CGPoint(x: 50, y: 75), zoom: 1.75)
        let world = CGPoint(x: -300, y: 410)
        let viaTransform = world.applying(camera.transform(in: size))
        #expect(viaTransform.isClose(to: camera.worldToView(world, in: size)))
    }

    @Test func zoomKeepsAnchorFixed() {
        let camera = Camera(center: CGPoint(x: 10, y: 20), zoom: 1)
        let anchor = CGPoint(x: 900, y: 120)
        let pinned = camera.viewToWorld(anchor, in: size)
        let zoomed = camera.zoomed(to: 3, anchor: anchor, in: size)
        #expect(zoomed.zoom == 3)
        #expect(zoomed.worldToView(pinned, in: size).isClose(to: anchor))
    }

    @Test func zoomIsClamped() {
        #expect(Camera(zoom: 100).zoom == Camera.maxZoom)
        #expect(Camera(zoom: 0).zoom == Camera.minZoom)
        #expect(Camera(zoom: .nan).zoom == 1)
        #expect(Camera().zoomed(to: 0.001, anchor: .zero, in: size).zoom == Camera.minZoom)
    }

    @Test func panMovesContentWithTheGesture() {
        var camera = Camera(zoom: 2)
        let world = CGPoint(x: 100, y: 100)
        let before = camera.worldToView(world, in: size)
        camera.pan(by: CGVector(dx: 30, dy: -12))
        let after = camera.worldToView(world, in: size)
        #expect(after.isClose(to: CGPoint(x: before.x + 30, y: before.y - 12)))
    }

    @Test func zoomStepsWalkThePresets() {
        #expect(Camera(zoom: 1).nextZoomStep(up: true) == 1.25)
        #expect(Camera(zoom: 1).nextZoomStep(up: false) == 0.75)
        #expect(Camera(zoom: 0.8).nextZoomStep(up: true) == 1)
        #expect(Camera(zoom: 8).nextZoomStep(up: true) == 8)
        #expect(Camera(zoom: 0.05).nextZoomStep(up: false) == 0.05)
    }

    @Test func fittingShowsTheWholeRect() {
        let rect = CGRect(x: -2000, y: 500, width: 4000, height: 1000)
        let camera = Camera.fitting(rect, in: size, padding: 80)
        let visible = camera.visibleWorldRect(in: size)
        #expect(visible.insetBy(dx: -0.001, dy: -0.001).contains(rect))
        #expect(camera.center == CGPoint(x: 0, y: 1000))
    }

    @Test func fittingNeverZoomsPastActualSize() {
        let camera = Camera.fitting(CGRect(x: 0, y: 0, width: 50, height: 50), in: size)
        #expect(camera.zoom == 1)
    }

    @Test func anchoredInterpolationKeepsAnchorFixed() {
        let anchor = CGPoint(x: 200, y: 650)
        let from = Camera(center: CGPoint(x: 40, y: -60), zoom: 0.5)
        let to = from.zoomed(to: 4, anchor: anchor, in: size)
        let pinned = from.viewToWorld(anchor, in: size)
        for t in stride(from: 0.0, through: 1.0, by: 0.125) {
            let mid = Camera.interpolate(from: from, to: to, progress: t, anchor: anchor, in: size)
            #expect(mid.worldToView(pinned, in: size).isClose(to: anchor))
        }
        #expect(Camera.interpolate(from: from, to: to, progress: 0.5, anchor: anchor, in: size).zoom.isClose(to: 1.41421356))
    }

    @Test func viewportRoundTrip() {
        let camera = Camera(center: CGPoint(x: 12, y: -34), zoom: 0.75)
        #expect(Camera(viewport: camera.viewport) == camera)
    }

    @Test func gridFadesOutWhenZoomedOut() {
        #expect(DotGrid.opacity(forZoom: 1) == 1)
        #expect(DotGrid.opacity(forZoom: 0.4) == 1)
        #expect(DotGrid.opacity(forZoom: 0.25) == 0)
        #expect(DotGrid.opacity(forZoom: 0.1) == 0)
    }
}

extension CGPoint {
    func isClose(to other: CGPoint, tolerance: CGFloat = 1e-6) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

extension CGFloat {
    func isClose(to other: CGFloat, tolerance: CGFloat = 1e-6) -> Bool {
        abs(self - other) <= tolerance
    }
}
