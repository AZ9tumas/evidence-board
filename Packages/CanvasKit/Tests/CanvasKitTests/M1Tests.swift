import AppKit
import Foundation
import Testing
import BoardKit
@testable import CanvasKit

@Suite("Spatial grid")
struct SpatialGridTests {
    @Test func findsOnlyIntersectingItems() {
        var grid = SpatialGrid(cellSize: 100)
        let a = UUID(), b = UUID(), c = UUID()
        grid.insert(a, rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        grid.insert(b, rect: CGRect(x: 400, y: 400, width: 50, height: 50))
        grid.insert(c, rect: CGRect(x: -1000, y: -1000, width: 5000, height: 5000)) // spans many cells

        #expect(grid.query(CGRect(x: 10, y: 10, width: 10, height: 10)) == [a, c])
        #expect(grid.query(CGPoint(x: 420, y: 420)) == [b, c])
        #expect(grid.query(CGRect(x: 4500, y: 4500, width: 10, height: 10)).isEmpty)
    }

    @Test func updatesAndRemovals() {
        var grid = SpatialGrid(cellSize: 100)
        let a = UUID()
        grid.insert(a, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        grid.insert(a, rect: CGRect(x: 900, y: 900, width: 10, height: 10))
        #expect(grid.query(CGPoint(x: 5, y: 5)).isEmpty)
        #expect(grid.query(CGPoint(x: 905, y: 905)) == [a])
        grid.remove(a)
        #expect(grid.count == 0)
        #expect(grid.query(CGPoint(x: 905, y: 905)).isEmpty)
    }

    @Test func zoomedFarOutQueryMatchesBruteForce() {
        var grid = SpatialGrid(cellSize: 64)
        var rects: [UUID: CGRect] = [:]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let id = UUID()
            let rect = CGRect(
                x: .random(in: -20_000...20_000, using: &generator), y: .random(in: -20_000...20_000, using: &generator),
                width: .random(in: 10...400, using: &generator), height: .random(in: 10...400, using: &generator)
            )
            rects[id] = rect
            grid.insert(id, rect: rect)
        }
        let query = CGRect(x: -15_000, y: -9_000, width: 30_000, height: 12_000)
        #expect(grid.query(query) == Set(rects.filter { $0.value.intersects(query) }.keys))
    }
}

@Suite("Card hit testing and resizing")
struct CardGeometryTests {
    private func card(rotation: Double = 0) -> Card {
        Card(
            frame: Rect(x: 0, y: 0, width: 200, height: 100), rotation: rotation,
            createdAt: .now, modifiedAt: .now, content: .text(TextPayload(content: "x"))
        )
    }

    @Test func containsFollowsRotation() {
        let flat = card()
        #expect(CanvasGeometry.contains(flat, point: CGPoint(x: 195, y: 5)))
        #expect(!CanvasGeometry.contains(flat, point: CGPoint(x: 205, y: 50)))

        let turned = card(rotation: 90) // now 100 wide and 200 tall around (100, 50)
        #expect(CanvasGeometry.contains(turned, point: CGPoint(x: 100, y: 140)))
        #expect(!CanvasGeometry.contains(turned, point: CGPoint(x: 190, y: 50)))
    }

    @Test func localAndWorldPointsRoundTrip() {
        let turned = card(rotation: 12)
        let world = CGPoint(x: 37, y: -18)
        let back = CanvasGeometry.worldPoint(CanvasGeometry.localPoint(world, in: turned), in: turned)
        #expect(back.isClose(to: world, tolerance: 1e-9))
    }

    @Test func resizeKeepsOppositeCornerFixed() {
        for rotation in [0.0, 7, -12] {
            let original = card(rotation: rotation)
            let fixedLocal = CGPoint(x: -100, y: -50) // top-left stays while dragging bottom-right
            let fixedBefore = CanvasGeometry.worldPoint(fixedLocal, in: original)
            let target = CanvasGeometry.worldPoint(CGPoint(x: 160, y: 90), in: original)

            var resized = original
            resized.frame = CanvasGeometry.resizedFrame(
                of: original, dragging: .bottomRight, to: target, minimumSize: CGSize(width: 10, height: 10)
            )
            #expect(abs(resized.frame.width - 260) < 1e-6)
            #expect(abs(resized.frame.height - 140) < 1e-6)
            let fixedAfter = CanvasGeometry.worldPoint(CGPoint(x: -130, y: -70), in: resized)
            #expect(fixedAfter.isClose(to: fixedBefore, tolerance: 1e-6))
        }
    }

    @Test func resizeRespectsMinimumSize() {
        let frame = CanvasGeometry.resizedFrame(
            of: card(), dragging: .topLeft, to: CGPoint(x: 500, y: 500), minimumSize: CGSize(width: 120, height: 64)
        )
        #expect(frame.width == 120 && frame.height == 64)
        #expect(frame.x + frame.width == 200 && frame.y + frame.height == 100) // bottom-right corner held
    }
}

@MainActor
@Suite("Text cards")
struct TextCardTests {
    static let appearance = CanvasAppearance(
        background: GradientPair(.black, .black), vignette: .clear, gridDot: .white,
        cardFill: GradientPair(.black, .black), cardStroke: GradientPair(.white, .white), skeleton: .white,
        pin: GradientPair(.white, .black), lockedPin: GradientPair(.white, .black), tints: [:],
        text: .white, codeText: .white, paperFill: GradientPair(.black, .black), paperText: .white,
        selection: GradientPair(.white, .white)
    )

    @Test func longerTextIsTaller() {
        let short = TextPayload(content: "One line")
        let long = TextPayload(content: String(repeating: "Several words that wrap across lines. ", count: 8))
        let shortHeight = TextCardTypography.fittingHeight(for: short, width: 260, appearance: Self.appearance)
        let longHeight = TextCardTypography.fittingHeight(for: long, width: 260, appearance: Self.appearance)
        #expect(shortHeight >= TextCardTypography.minimumSize.height)
        #expect(longHeight > shortHeight + 60)
        #expect(TextCardTypography.fittingHeight(for: long, width: 520, appearance: Self.appearance) < longHeight)
    }

    @Test func emptyCardIsOneLineTall() {
        let empty = TextCardTypography.fittingHeight(for: TextPayload(content: ""), width: 260, appearance: Self.appearance)
        let oneLine = TextCardTypography.fittingHeight(for: TextPayload(content: "x"), width: 260, appearance: Self.appearance)
        #expect(empty == oneLine)
    }

    @Test func markdownBecomesFormatting() {
        let text = TextPayload(content: "Plain **bold** and `code`")
        let attributed = TextCardTypography.attributedText(for: text, appearance: Self.appearance)
        #expect(attributed.string == "Plain bold and code")
        let boldFont = attributed.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let codeFont = attributed.attribute(.font, at: 16, effectiveRange: nil) as? NSFont
        #expect(codeFont?.isFixedPitch == true)
    }

    @Test func rendersAtTheRequestedScale() throws {
        let image = try #require(TextCardTypography.render(
            TextPayload(content: "Harbor"), size: CGSize(width: 260, height: 90), scale: 2, appearance: Self.appearance
        ))
        #expect(image.width == 520 && image.height == 180)
    }

    @Test func renderedTextIsUprightAndInsideTheInsets() throws {
        let image = try #require(TextCardTypography.render(
            TextPayload(content: "█████", style: .headline), size: CGSize(width: 260, height: 200), scale: 1,
            appearance: Self.appearance
        ))
        let rep = NSBitmapImageRep(cgImage: image)
        func alpha(_ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        // Row 0 of the bitmap is the top of the card: ink sits just under the top inset,
        // nothing at the very top or bottom.
        let inkRows = (0..<image.height).filter { y in (0..<image.width).contains { alpha($0, y) > 0.5 } }
        let first = try #require(inkRows.first)
        #expect(first >= Int(TextCardTypography.insets.top) - 2)
        #expect(first < 70)
        #expect(try #require(inkRows.last) < image.height - 60)
    }

    @Test func tiersRoundUp() {
        #expect(BoardCanvasView.tier(for: 0.1) == 0.25)
        #expect(BoardCanvasView.tier(for: 0.3) == 0.5)
        #expect(BoardCanvasView.tier(for: 1) == 1)
        #expect(BoardCanvasView.tier(for: 1.2) == 2)
        #expect(BoardCanvasView.tier(for: 8) == 4)
    }

    @Test func detailLevelsFollowZoom() {
        #expect(DetailLevel(zoom: 0.1) == .minimal)
        #expect(DetailLevel(zoom: 0.2) == .reduced)
        #expect(DetailLevel(zoom: 0.4) == .full)
    }
}
