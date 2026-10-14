import Foundation
import Testing
@testable import BoardKit

@Suite("Board validation")
struct BoardValidatorTests {
    let a = "00000000-0000-0000-0000-00000000000A"
    let b = "00000000-0000-0000-0000-00000000000B"

    @Test func skipsUnknownCardTypesButKeepsTheRest() throws {
        let json = board(cards: [
            textCard(id: a),
            #"{ "id": "\#(b)", "type": "video", "frame": { "x": 0, "y": 0, "width": 10, "height": 10 } }"#,
        ])
        let result = try BoardCodec.decode(json)
        #expect(result.board.cards.map(\.id.uuidString) == [a])
        #expect(result.report.skippedCards == 1)
        #expect(result.report.summary == "1 item couldn't be loaded.")
    }

    @Test func skipsCardsWhosePayloadDoesNotMatchTheirType() throws {
        let json = board(cards: [
            #"{ "id": "\#(a)", "type": "image", "frame": { "x": 0, "y": 0, "width": 10, "height": 10 }, "text": { "content": "x" } }"#,
        ])
        let result = try BoardCodec.decode(json)
        #expect(result.board.cards.isEmpty)
        #expect(result.report.skippedCards == 1)
    }

    @Test func skipsWebCardsThatAreNotHTTP() throws {
        let json = board(cards: [
            #"{ "id": "\#(a)", "type": "web", "frame": { "x": 0, "y": 0, "width": 10, "height": 10 }, "web": { "url": "javascript:alert(1)" } }"#,
            #"{ "id": "\#(b)", "type": "web", "frame": { "x": 0, "y": 0, "width": 10, "height": 10 }, "web": { "url": "HTTPS://example.com" } }"#,
        ])
        let result = try BoardCodec.decode(json)
        #expect(result.board.cards.map(\.id.uuidString) == [b])
        #expect(result.report.skippedCards == 1)
    }

    @Test func skipsDuplicateCardIDs() throws {
        let result = try BoardCodec.decode(board(cards: [textCard(id: a), textCard(id: a)]))
        #expect(result.board.cards.count == 1)
        #expect(result.report.skippedCards == 1)
    }

    @Test func dropsDanglingAndSelfLoopStrings() throws {
        let missing = "00000000-0000-0000-0000-00000000000C"
        let json = board(
            cards: [textCard(id: a), textCard(id: b)],
            strings: [
                string(id: "10000000-0000-0000-0000-000000000001", from: a, to: b),
                string(id: "10000000-0000-0000-0000-000000000002", from: a, to: missing),
                string(id: "10000000-0000-0000-0000-000000000003", from: a, to: a),
                string(id: "10000000-0000-0000-0000-000000000001", from: b, to: a),
            ]
        )
        let result = try BoardCodec.decode(json)
        #expect(result.board.strings.count == 1)
        #expect(result.report.skippedStrings == 3)
        #expect(result.report.summary == "3 items couldn't be loaded.")
    }

    @Test func clampsOutOfRangeNumbers() throws {
        let json = board(
            cards: [
                #"{ "id": "\#(a)", "type": "text", "rotation": 40, "frame": { "x": 0, "y": 0, "width": -5, "height": 20 }, "text": { "content": "x" } }"#,
                textCard(id: b),
            ],
            strings: [
                #"{ "id": "10000000-0000-0000-0000-000000000001", "from": "\#(a)", "to": "\#(b)", "thickness": 9, "sag": -1 }"#,
            ],
            viewport: #"{ "x": 0, "y": 0, "zoom": 100 }"#
        )
        let result = try BoardCodec.decode(json)
        let card = try #require(result.board.cards.first)
        let string = try #require(result.board.strings.first)
        #expect(card.rotation == 15)
        #expect(card.frame.width == 1)
        #expect(string.thickness == 4)
        #expect(string.sag == 0)
        #expect(result.board.viewport.zoom == 8)
        #expect(result.report.adjustedValues == 5)
        #expect(result.report.summary == nil)
    }

    @Test func unknownEnumValuesFallBackToDefaults() throws {
        let json = board(
            cards: [
                #"{ "id": "\#(a)", "type": "text", "tint": "plaid", "frame": { "x": 0, "y": 0, "width": 10, "height": 10 }, "text": { "content": "x", "style": "comic-sans" } }"#,
                textCard(id: b),
            ],
            strings: [
                ##"{ "id": "10000000-0000-0000-0000-000000000001", "from": "\##(a)", "to": "\##(b)", "color": "#00ff88", "style": "wavy" }"##,
            ],
            theme: "neon"
        )
        let result = try BoardCodec.decode(json)
        let card = try #require(result.board.cards.first)
        #expect(card.tint == nil)
        #expect(card.content == .text(TextPayload(content: "x", style: .note)))
        #expect(result.board.strings.first?.color == .hex("#00FF88"))
        #expect(result.board.strings.first?.stroke == .solid)
        #expect(result.board.theme == .system)
    }

    @Test func skipsMalformedAssets() throws {
        let json = board(assets: #"{ "sha256-good": { "mime": "image/png", "data": "AAEC" }, "sha256-bad": { "mime": 7 } }"#)
        let result = try BoardCodec.decode(json)
        #expect(result.board.assets.keys.sorted() == ["sha256-good"])
        #expect(result.report.skippedAssets == 1)
    }

    // MARK: - JSON builders

    private func textCard(id: String) -> String {
        #"{ "id": "\#(id)", "type": "text", "frame": { "x": 0, "y": 0, "width": 100, "height": 60 }, "text": { "content": "note" } }"#
    }

    private func string(id: String, from: String, to: String) -> String {
        #"{ "id": "\#(id)", "from": "\#(from)", "to": "\#(to)" }"#
    }

    private func board(
        cards: [String] = [],
        strings: [String] = [],
        assets: String = "{}",
        viewport: String = #"{ "x": 0, "y": 0, "zoom": 1 }"#,
        theme: String = "noir"
    ) -> Data {
        Data("""
        {
          "format": "evidenceboard",
          "formatVersion": 1,
          "theme": "\(theme)",
          "viewport": \(viewport),
          "cards": [\(cards.joined(separator: ","))],
          "strings": [\(strings.joined(separator: ","))],
          "assets": \(assets)
        }
        """.utf8)
    }
}
