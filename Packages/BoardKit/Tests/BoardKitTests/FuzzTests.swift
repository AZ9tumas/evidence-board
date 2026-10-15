import Foundation
import Testing
@testable import BoardKit

/// Throws mangled boards at the loader (DESIGN.md §13, §15). Whatever comes in, decoding must
/// either fail cleanly or produce a board the rest of the app can trust, and saving that board
/// and loading it again must change nothing.
///
/// The mutations are seeded, so a failure always reproduces. CI also runs a coverage-guided
/// libFuzzer harness over the same checks (`Tools/Fuzz`).
@Suite("Fuzzing the loader")
struct FuzzTests {
    /// A small board that touches every feature of the format.
    static let seed: Data = {
        let json = """
        {
          "format": "evidenceboard", "formatVersion": 1, "id": "9C2B3D4E-1F20-4A5B-8C6D-7E8F9A0B1C2D",
          "title": "Fuzz", "theme": "cork", "createdAt": "2026-10-14T09:12:44Z", "modifiedAt": "2026-10-14T09:12:44.5Z",
          "viewport": { "x": 10, "y": -20, "zoom": 1.5 },
          "cards": [
            { "id": "11111111-1111-4111-8111-111111111111", "type": "text", "frame": { "x": 0, "y": 0, "width": 260, "height": 120 },
              "rotation": 2, "z": 1, "tint": "amber", "locked": false, "createdAt": "2026-10-14T09:12:44Z", "modifiedAt": "2026-10-14T09:12:44Z",
              "text": { "content": "Ferry left **11 minutes early**", "style": "note", "alignment": "leading", "autoHeight": true } },
            { "id": "22222222-2222-4222-8222-222222222222", "type": "image", "frame": { "x": 400, "y": 0, "width": 240, "height": 280 },
              "rotation": 0, "z": 2, "locked": true, "createdAt": "2026-10-14T09:12:44Z", "modifiedAt": "2026-10-14T09:12:44Z",
              "image": { "asset": "sha256-abc", "caption": "Dock camera", "frameStyle": "polaroid", "crop": { "x": 0.1, "y": 0.1, "width": 0.5, "height": 0.5 } } },
            { "id": "33333333-3333-4333-8333-333333333333", "type": "web", "frame": { "x": 800, "y": 0, "width": 360, "height": 340 },
              "rotation": 0, "z": 3, "locked": false, "createdAt": "2026-10-14T09:12:44Z", "modifiedAt": "2026-10-14T09:12:44Z",
              "web": { "url": "https://example.com/a", "snapshot": { "fetchedAt": "2026-10-14T09:20:00Z", "variant": "media",
                "title": "Night logs", "description": "Three departures", "siteName": "Example", "author": "J. Rivera",
                "publishedAt": "2026-10-12T00:00:00Z", "mediaDuration": 754, "image": "sha256-abc", "icon": null,
                "palette": { "vibrant": "#3A7BFF", "muted": "#5C6A88", "darkVibrant": "#12306E", "darkMuted": "#1B2235", "light": "#E8EEFF" } } } }
          ],
          "strings": [
            { "id": "44444444-4444-4444-8444-444444444444", "from": "11111111-1111-4111-8111-111111111111",
              "to": "22222222-2222-4222-8222-222222222222", "color": "red", "thickness": 2, "sag": 0.5, "style": "dashed",
              "arrow": "forward", "label": "same night" },
            { "id": "55555555-5555-4555-8555-555555555555", "from": "22222222-2222-4222-8222-222222222222",
              "to": "33333333-3333-4333-8333-333333333333", "color": "#FF00AA", "thickness": 3, "sag": 0.2 }
          ],
          "assets": { "sha256-abc": { "mime": "image/png", "pixelWidth": 1, "pixelHeight": 1,
            "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" } }
        }
        """
        return Data(json.utf8)
    }()

    /// Decoding `data` either throws or gives a sound board that survives a save and reload.
    static func checkLoader(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let first = try? BoardCodec.decode(data) else { return }
        let board = first.board
        let ids = Set(board.cards.map(\.id))
        #expect(ids.count == board.cards.count, "duplicate cards survived", sourceLocation: sourceLocation)
        #expect(Set(board.strings.map(\.id)).count == board.strings.count, "duplicate strings survived", sourceLocation: sourceLocation)
        for string in board.strings {
            #expect(string.from != string.to && ids.contains(string.from) && ids.contains(string.to), "dangling string", sourceLocation: sourceLocation)
            #expect(BoardString.thicknessRange.contains(string.thickness) && BoardString.sagRange.contains(string.sag), sourceLocation: sourceLocation)
        }
        for card in board.cards {
            #expect(card.frame.width.isFinite && card.frame.width >= 1 && card.frame.height >= 1, sourceLocation: sourceLocation)
            #expect(Card.rotationRange.contains(card.rotation), sourceLocation: sourceLocation)
            if case .web(let web) = card.content { #expect(web.url.isWebURL, sourceLocation: sourceLocation) }
        }
        #expect(Viewport.zoomRange.contains(board.viewport.zoom), sourceLocation: sourceLocation)

        // Saving never fails, and saving what was loaded back is a fixed point.
        let saved: Data
        do {
            saved = try BoardCodec.encode(board)
        } catch {
            Issue.record("a loaded board couldn't be saved: \(error)", sourceLocation: sourceLocation)
            return
        }
        guard let second = try? BoardCodec.decode(saved) else {
            Issue.record("a saved board couldn't be loaded again", sourceLocation: sourceLocation)
            return
        }
        #expect(second.report.skippedItems == 0 && second.report.adjustedValues == 0, "\(second.report)", sourceLocation: sourceLocation)
        #expect((try? BoardCodec.encode(second.board)) == saved, "saving a reloaded board changed it", sourceLocation: sourceLocation)
    }

    @Test func theSeedLoadsCleanly() throws {
        let result = try BoardCodec.decode(Self.seed)
        #expect(result.report == LoadReport())
        #expect(result.board.cards.count == 3 && result.board.strings.count == 2)
        Self.checkLoader(Self.seed)
    }

    /// Flipped, inserted, deleted and duplicated bytes, and truncation.
    @Test func byteMutations() {
        var random = Seeded(seed: 0xB0A2D)
        let seed = [UInt8](Self.seed)
        for _ in 0..<3000 {
            var bytes = seed
            for _ in 0..<random.int(in: 1...4) {
                guard !bytes.isEmpty else { break }
                let at = random.int(in: 0...(bytes.count - 1))
                switch random.int(in: 0...4) {
                case 0: bytes[at] = UInt8(truncatingIfNeeded: random.next())
                case 1: bytes.insert(contentsOf: random.pick(Self.tokens).utf8, at: at)
                case 2: bytes.removeSubrange(at..<min(at + random.int(in: 1...40), bytes.count))
                case 3:
                    let end = min(at + random.int(in: 1...200), bytes.count)
                    bytes.insert(contentsOf: bytes[at..<end], at: random.int(in: 0...bytes.count))
                default: bytes.removeSubrange(at...)
                }
            }
            Self.checkLoader(Data(bytes))
        }
    }

    /// Replaced values (wrong types, extremes, huge text), removed keys, duplicated and
    /// cross-wired items, inside otherwise valid JSON.
    @Test func structuralMutations() throws {
        var random = Seeded(seed: 0x57_2C7)
        let original = try JSONSerialization.jsonObject(with: Self.seed)
        for _ in 0..<2500 {
            var tree = original
            for _ in 0..<random.int(in: 1...3) { tree = Self.mutate(tree, random: &random, depth: 0) }
            guard JSONSerialization.isValidJSONObject(tree),
                  let data = try? JSONSerialization.data(withJSONObject: tree) else { continue }
            Self.checkLoader(data)
        }
    }

    @Test func pathologicalInputs() {
        let cases: [String] = [
            "", "{}", "[]", "null", "\"evidenceboard\"",
            String(repeating: "[", count: 100_000),
            "{\"format\":\"evidenceboard\",\"cards\":" + String(repeating: "[", count: 10_000) + "}",
            "{\"format\":\"evidenceboard\",\"formatVersion\":999}",
            "{\"format\":\"evidenceboard\",\"viewport\":{\"x\":1e308,\"y\":-1e308,\"zoom\":1e-308}}",
            "{\"format\":\"evidenceboard\",\"cards\":[{\"type\":\"text\",\"frame\":{\"x\":1e999,\"y\":0,\"width\":-5,\"height\":1e308},\"text\":{\"content\":\"x\"}}]}",
            "{\"format\":\"evidenceboard\",\"title\":\"" + String(repeating: "é", count: 50_000) + "\"}",
        ]
        for text in cases { Self.checkLoader(Data(text.utf8)) }
    }

    @Test func oversizedTextIsCut() throws {
        var tree = try JSONSerialization.jsonObject(with: Self.seed) as! [String: Any]
        var cards = tree["cards"] as! [[String: Any]]
        var text = cards[0]["text"] as! [String: Any]
        text["content"] = String(repeating: "a", count: BoardValidator.maxTextLength + 10)
        cards[0]["text"] = text
        var image = cards[1]["image"] as! [String: Any]
        image["crop"] = ["x": -3, "y": 0.5, "width": 4, "height": 0.25]
        cards[1]["image"] = image
        tree["cards"] = cards
        let result = try BoardCodec.decode(JSONSerialization.data(withJSONObject: tree))
        guard case .text(let payload) = result.board.cards[0].content, case .image(let photo) = result.board.cards[1].content else {
            Issue.record("cards changed kind")
            return
        }
        #expect(payload.content.count == BoardValidator.maxTextLength)
        #expect(photo.crop == Rect(x: 0, y: 0.5, width: 1, height: 0.25))
        #expect(result.report.adjustedValues == 2)
    }

    // MARK: Mutation helpers

    static let tokens = ["{", "}", "[", "]", ",", ":", "\"", "null", "true", "-1", "1e309", "0.0000001", "\"\\u0000\"", "\"\\uD800\"", "NaN", "\"cards\"", "\"id\""]

    static func randomValue(_ random: inout Seeded) -> Any {
        switch random.int(in: 0...11) {
        case 0: return NSNull()
        case 1: return random.int(in: 0...1) == 0
        case 2: return Double.greatestFiniteMagnitude
        case 3: return -Double.greatestFiniteMagnitude
        case 4: return Double.leastNonzeroMagnitude
        case 5: return Int.max
        case 6: return random.int(in: -1000...1000)
        case 7: return ""
        case 8: return String(repeating: "🧵", count: random.int(in: 1...20_000))
        case 9: return "javascript:alert(1)"
        case 10: return [Any]()
        default: return [String: Any]()
        }
    }

    static func mutate(_ node: Any, random: inout Seeded, depth: Int) -> Any {
        let here = depth > 0 && random.int(in: 0...5) == 0
        if here { return randomValue(&random) }
        if var object = node as? [String: Any], !object.isEmpty {
            let keys = object.keys.sorted()
            let key = random.pick(keys)
            switch random.int(in: 0...5) {
            case 0: object[key] = nil
            case 1: object[key] = randomValue(&random)
            default: object[key] = mutate(object[key]!, random: &random, depth: depth + 1)
            }
            return object
        }
        if var array = node as? [Any], !array.isEmpty {
            let index = random.int(in: 0...(array.count - 1))
            switch random.int(in: 0...5) {
            case 0: array.remove(at: index)
            case 1: array.append(array[index]) // duplicate IDs
            case 2: array.swapAt(index, random.int(in: 0...(array.count - 1)))
            default: array[index] = mutate(array[index], random: &random, depth: depth + 1)
            }
            return array
        }
        return random.int(in: 0...1) == 0 ? randomValue(&random) : node
    }
}

/// A small seeded random generator (SplitMix64), so fuzz runs reproduce.
struct Seeded {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(in: 0...(items.count - 1))]
    }
}
