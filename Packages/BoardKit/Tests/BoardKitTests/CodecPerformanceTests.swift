import Foundation
import Testing
@testable import BoardKit

/// Save and open budgets for a 50 MB board (DESIGN.md §11). They only mean something in an
/// optimized build, so they run when `EB_PERF` is set:
///
///     EB_PERF=1 swift test -c release -Xswiftc -enable-testing --filter CodecPerformanceTests
@Suite("Codec performance budgets", .enabled(if: ProcessInfo.processInfo.environment["EB_PERF"] != nil), .serialized)
struct CodecPerformanceTests {
    static func check(_ name: String, _ measured: Double, under budget: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        let pass = measured <= budget
        print("BUDGET|\(name)|\(String(format: "%.2f", measured)) ms|< \(budget.formatted()) ms|\(pass ? "pass" : "FAIL")")
        #expect(pass, "\(name): \(measured) ms, budget \(budget) ms", sourceLocation: sourceLocation)
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// 300 cards: 100 photos of about 500 KB each, the rest text, with 150 strings.
    static func bigBoard() -> Board {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        var board = Board.new(title: "Big", now: stamp)
        var generator = SystemRandomNumberGenerator()
        for index in 0..<300 {
            let frame = Rect(x: Double(index % 20) * 420, y: Double(index / 20) * 340, width: 300, height: 220)
            let content: CardContent
            if index % 3 == 0 {
                let bytes = (0..<500_000).map { _ in UInt8.random(in: 0...255, using: &generator) }
                let id = "sha256-perf-\(index)"
                board.assets[id] = Asset(mime: "image/jpeg", pixelWidth: 1400, pixelHeight: 1050, data: Data(bytes))
                content = .image(ImagePayload(asset: id, caption: "Exhibit \(index)"))
            } else {
                content = .text(TextPayload(content: "Card \(index): the ferry left eleven minutes early, and nobody has said why."))
            }
            board.cards.append(Card(frame: frame, z: index, createdAt: stamp, modifiedAt: stamp, content: content))
        }
        board.strings = (0..<150).map { BoardString(from: board.cards[$0].id, to: board.cards[$0 + 1].id) }
        return board
    }

    @Test func saveAndOpenA50MBBoard() throws {
        let board = Self.bigBoard()
        let clock = ContinuousClock()
        _ = try BoardCodec.encode(board) // warm up

        var start = clock.now
        let data = try BoardCodec.encode(board)
        Self.check("Save 50 MB board (encode, off the main thread)", Self.milliseconds(clock.now - start), under: 300)
        #expect(data.count > 45_000_000)
        print("BUDGET-INFO|saved board|\(data.count / 1_048_576) MB")

        start = clock.now
        let loaded = try BoardCodec.decode(data)
        Self.check("Open 50 MB board (decode and validate)", Self.milliseconds(clock.now - start), under: 500)
        #expect(loaded.board.cards.count == 300 && loaded.report == LoadReport())
    }
}
