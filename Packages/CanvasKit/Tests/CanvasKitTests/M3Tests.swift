import AppKit
import Foundation
import Testing
import BoardKit
@testable import CanvasKit

@Suite("String geometry")
struct StringGeometryTests {
    let a = CGPoint(x: 0, y: 0)
    let b = CGPoint(x: 400, y: 0)

    @Test func curveRunsFromPinToPin() {
        let points = CanvasGeometry.stringCurve(from: a, to: b, sag: 0.5).flattened()
        #expect(points.count == 17)
        #expect(points.first == a && points.last == b)
        // It hangs below the chord: world y grows downward.
        #expect(points[8].y > 0)
    }

    @Test func reversedCurveTracesTheSamePath() {
        let curve = CanvasGeometry.stringCurve(from: a, to: CGPoint(x: 300, y: 180), sag: 0.7, fan: 1)
        for step in 0...10 {
            let t = CGFloat(step) / 10
            let forward = curve.point(at: t)
            let backward = curve.reversed.point(at: 1 - t)
            #expect(abs(forward.x - backward.x) < 1e-9 && abs(forward.y - backward.y) < 1e-9)
        }
    }

    @Test func middleFollowsASagDrag() {
        let before = CanvasGeometry.stringCurve(from: a, to: b, sag: 0.3).point(at: 0.5)
        let sag = CanvasGeometry.sag(0.3, afterDragging: 10, from: a, to: b)
        let after = CanvasGeometry.stringCurve(from: a, to: b, sag: sag).point(at: 0.5)
        #expect(abs(after.y - before.y - 10) < 1e-9)
        #expect(CanvasGeometry.sag(0.3, afterDragging: 10_000, from: a, to: b) == 1)
        #expect(CanvasGeometry.sag(0.3, afterDragging: -10_000, from: a, to: b) == 0)
    }

    @Test func extraDroopAddsSlack() {
        let resting = CanvasGeometry.stringCurve(from: a, to: b, sag: 0.5).point(at: 0.5).y
        let slack = CanvasGeometry.stringCurve(from: a, to: b, sag: 0.5, droopScale: 1.3).point(at: 0.5).y
        #expect(abs(slack - resting * 1.3) < 1e-9)
    }

    @Test func distanceToAPolyline() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        #expect(CanvasGeometry.distance(from: CGPoint(x: 50, y: 6), to: line) == 6)
        #expect(CanvasGeometry.distance(from: CGPoint(x: 104, y: 50), to: line) == 4)
        #expect(CanvasGeometry.distance(from: CGPoint(x: -3, y: -4), to: line) == 5)
        #expect(CanvasGeometry.length(of: line) == 200)
    }

    @Test func arrowheadsSitJustBeforeTheEnd() throws {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 30, y: 0)]
        let found = try #require(CanvasGeometry.point(on: line, distanceFromEnd: 15))
        #expect(found.point == CGPoint(x: 15, y: 0))
        #expect(found.direction == CGVector(dx: 1, dy: 0))
        // Further back than the line is long clamps to its start.
        #expect(CanvasGeometry.point(on: line, distanceFromEnd: 99)?.point == CGPoint(x: 0, y: 0))
    }

    @Test func boundsContainTheCurve() {
        let curve = CanvasGeometry.stringCurve(from: CGPoint(x: -50, y: 20), to: CGPoint(x: 260, y: -90), sag: 1, fan: -1)
        let box = curve.bounds.insetBy(dx: -0.001, dy: -0.001)
        #expect(curve.flattened(segments: 64).allSatisfy { box.contains($0) })
    }
}

@Suite("Springs")
struct SpringTests {
    @Test func settlesOnTheTarget() {
        var spring = Spring(value: 1.3, target: 1, response: 0.45, damping: 0.6)
        var lowest: CGFloat = 2
        for _ in 0..<240 {
            spring.step(1.0 / 120)
            lowest = min(lowest, spring.value)
        }
        #expect(spring.isSettled())
        // Underdamped: it swings past the target once, like a string pulled taut.
        #expect(lowest < 1)
    }

    @Test func waitsOutItsDelay() {
        var spring = Spring(value: 0, target: 1, response: 0.2, damping: 1, delay: 0.1)
        spring.step(0.05)
        #expect(spring.value == 0)
        spring.step(0.2)
        #expect(spring.value > 0.5)
    }
}

@MainActor
@Suite("String node")
struct StringNodeTests {
    @Test func labelSitsAtTheMiddleAndCountsForHits() throws {
        let string = BoardString(from: UUID(), to: UUID(), arrow: .both, label: "same night")
        let node = StringNode(string: string, appearance: TextCardTests.appearance, detail: .full, zoom: 1, scale: 2, labelScale: 2)
        node.update(string: string, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 400, y: 100), fan: 0, appearance: TextCardTests.appearance)

        let label = try #require(node.labelFrame)
        let middle = node.curve.point(at: 0.5)
        #expect(abs(label.midX - middle.x) < 0.001 && abs(label.midY - middle.y) < 0.001)
        #expect(node.hitBounds.contains(label))
        #expect(node.showsLabel)
        #expect(node.polyline.count == 17)
        #expect(node.length > 400)

        node.setDetail(.reduced, zoom: 0.3)
        #expect(!node.showsLabel)
        node.setDetail(.full, zoom: 1)
        node.setEmphasis(.dimmed)
        #expect(!node.showsLabel)
    }
}
