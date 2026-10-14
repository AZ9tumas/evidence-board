import Foundation
import Testing
@testable import BoardKit

@Suite("Board codec")
struct BoardCodecTests {
    /// The sample board published in `docs/examples`, so the docs can never drift from the code.
    static let sampleURL = URL(filePath: #filePath)
        .deletingLastPathComponent() // BoardKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // BoardKit
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root
        .appending(path: "docs/examples/harbor-case.evboard")

    @Test func loadsPublishedSample() throws {
        let result = try BoardCodec.decode(Data(contentsOf: Self.sampleURL))
        let board = result.board

        #expect(result.report == LoadReport())
        #expect(board.title == "Case 042 — The Harbor Files")
        #expect(board.theme == .noir)
        #expect(board.cards.map(\.kind) == [.text, .text, .image, .web, .text])
        #expect(board.strings.count == 3)
        #expect(board.assets.count == 3)
        #expect(board.referencedAssetIDs == Set(board.assets.keys))

        guard case .web(let web) = board.cards[3].content else {
            Issue.record("Expected a web card")
            return
        }
        #expect(web.url.absoluteString == "https://example.com/harbor-report")
        #expect(web.snapshot?.variant == .article)
        #expect(web.snapshot?.pageDescription?.hasPrefix("The logs show") == true)
        #expect(web.snapshot?.mediaDuration == nil)

        let dashed = try #require(board.strings.first { $0.stroke == .dashed })
        #expect(dashed.color == .tint(.azure))
        #expect(dashed.label == "contradicts?")
    }

    @Test func sampleImagesDecode() throws {
        let board = try BoardCodec.decode(Data(contentsOf: Self.sampleURL)).board
        for asset in board.assets.values {
            let data = try #require(asset.decodedData())
            #expect(data.count == asset.byteCount)
            #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47])) // PNG signature
        }
    }

    @Test func roundTripsLosslessly() throws {
        let original = try BoardCodec.decode(Data(contentsOf: Self.sampleURL)).board
        let reloaded = try BoardCodec.decode(BoardCodec.encode(original)).board
        #expect(reloaded == original)
    }

    @Test func encodingIsStable() throws {
        let board = try BoardCodec.decode(Data(contentsOf: Self.sampleURL)).board
        let first = try BoardCodec.encode(board)
        let second = try BoardCodec.encode(BoardCodec.decode(first).board)
        #expect(first == second)
    }

    @Test func writesFormatHeaderAndReadableURLs() throws {
        let board = try BoardCodec.decode(Data(contentsOf: Self.sampleURL)).board
        let json = try #require(String(data: BoardCodec.encode(board), encoding: .utf8))
        #expect(json.contains(#""format" : "evidenceboard""#))
        #expect(json.contains(#""formatVersion" : 1"#))
        #expect(json.contains("https://example.com/harbor-report"))
        #expect(json.contains(#""createdAt" : "2026-10-14T09:12:44Z""#))
    }

    @Test func newBoardRoundTrips() throws {
        let board = Board.new(title: "Case 1", now: Date(timeIntervalSince1970: 1_800_000_000.75))
        #expect(board.createdAt == Date(timeIntervalSince1970: 1_800_000_000))
        let reloaded = try BoardCodec.decode(BoardCodec.encode(board))
        #expect(reloaded.board == board)
        #expect(reloaded.report == LoadReport())
    }

    @Test func dropsUnreferencedAssetsOnSave() throws {
        var board = Board.new()
        board.assets["sha256-unused"] = Asset(mime: "image/png", data: Data([1, 2, 3]))
        let reloaded = try BoardCodec.decode(BoardCodec.encode(board)).board
        #expect(reloaded.assets.isEmpty)
    }

    @Test func acceptsFractionalSecondDates() throws {
        let json = minimalBoard(extra: #""createdAt": "2026-10-14T09:12:44.250Z""#)
        let board = try BoardCodec.decode(json).board
        #expect(abs(board.createdAt.timeIntervalSince1970 - 1_791_969_164.25) < 0.001)
    }

    @Test func rejectsFilesThatAreNotBoards() {
        #expect(throws: BoardLoadError.notAnEvidenceBoard) {
            try BoardCodec.decode(Data(#"{ "hello": "world" }"#.utf8))
        }
        #expect(throws: BoardLoadError.self) {
            try BoardCodec.decode(Data("not json".utf8))
        }
    }

    @Test func rejectsNewerFormats() {
        let json = Data(#"{ "format": "evidenceboard", "formatVersion": 99 }"#.utf8)
        #expect(throws: BoardLoadError.newerFormat(99)) {
            try BoardCodec.decode(json)
        }
    }

    @Test func fillsDefaultsForMinimalFiles() throws {
        let board = try BoardCodec.decode(minimalBoard()).board
        #expect(board.title == "Untitled Board")
        #expect(board.theme == .system)
        #expect(board.viewport == Viewport())
        #expect(board.cards.isEmpty)
    }

    private func minimalBoard(extra: String? = nil) -> Data {
        let fields = [#""format": "evidenceboard""#, #""formatVersion": 1"#] + (extra.map { [$0] } ?? [])
        return Data("{ \(fields.joined(separator: ", ")) }".utf8)
    }
}
