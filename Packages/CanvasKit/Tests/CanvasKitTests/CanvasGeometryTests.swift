import CoreGraphics
import Foundation
import Testing
import BoardKit
@testable import CanvasKit

@Suite("Canvas geometry")
struct CanvasGeometryTests {
    private func card(x: Double = 0, y: Double = 0, width: Double = 200, height: Double = 100, rotation: Double = 0) -> Card {
        Card(
            frame: Rect(x: x, y: y, width: width, height: height),
            rotation: rotation,
            createdAt: .now,
            modifiedAt: .now,
            content: .text(TextPayload(content: "x"))
        )
    }

    @Test func pinSitsAtTopCenter() {
        let pin = CanvasGeometry.pinPoint(of: card(x: 100, y: 50))
        #expect(pin.isClose(to: CGPoint(x: 200, y: 50 + CanvasGeometry.pinInset)))
    }

    @Test func pinFollowsClockwiseRotation() {
        // Rotated a quarter turn clockwise, the top edge faces right.
        let pin = CanvasGeometry.pinPoint(of: card(width: 200, height: 100, rotation: 90))
        #expect(pin.isClose(to: CGPoint(x: 100 + 50 - CanvasGeometry.pinInset, y: 50)))
    }

    @Test func rotatedBoundingBoxGrows() {
        let box = CanvasGeometry.boundingBox(of: card(width: 100, height: 100, rotation: 45))
        let diagonal = 100 * 2.0.squareRoot()
        #expect(box.width.isClose(to: diagonal, tolerance: 1e-4))
        #expect(CGPoint(x: box.midX, y: box.midY).isClose(to: CGPoint(x: 50, y: 50), tolerance: 1e-4))
    }

    @Test func contentBoundsCoverEveryCard() {
        let bounds = CanvasGeometry.contentBounds(of: [card(x: -500, y: 20), card(x: 300, y: 400, height: 80)])
        #expect(bounds == CGRect(x: -500, y: 20, width: 1000, height: 460))
        #expect(CanvasGeometry.contentBounds(of: []) == nil)
    }

    @Test func stringRunsPinToPinAndSags() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 400, y: 0)
        let path = CanvasGeometry.stringPath(from: a, to: b, sag: 0.5)
        #expect(path.currentPoint.isClose(to: b))
        let box = path.boundingBoxOfPath
        #expect(box.minX.isClose(to: 0) && box.maxX.isClose(to: 400))
        #expect(box.maxY > 20) // hangs below the straight line (y grows downward)
        #expect(box.minY.isClose(to: 0))
    }

    @Test func looserStringsSagMore() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 400, y: 0)
        let taut = CanvasGeometry.stringPath(from: a, to: b, sag: 0).boundingBoxOfPath.maxY
        let loose = CanvasGeometry.stringPath(from: a, to: b, sag: 1).boundingBoxOfPath.maxY
        #expect(loose > taut)
    }

    @Test func parallelStringsFanOut() {
        let a = UUID(), b = UUID(), c = UUID()
        let strings = [
            BoardString(from: a, to: b),
            BoardString(from: b, to: a),
            BoardString(from: a, to: b),
            BoardString(from: a, to: c),
        ]
        let offsets = CanvasGeometry.fanOffsets(for: strings)
        #expect(strings[0...2].map { offsets[$0.id]! } == [-1, 0, 1])
        #expect(offsets[strings[3].id] == 0)
    }
}
