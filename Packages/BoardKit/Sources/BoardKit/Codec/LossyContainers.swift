import Foundation

/// Decodes a JSON array, skipping elements that fail instead of failing the whole array.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element] = []
    var failures = 0

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            let index = container.currentIndex
            if let element = try? container.decode(Element.self) {
                elements.append(element)
                continue
            }
            failures += 1
            // A failed decode doesn't advance the container, so step over the bad element.
            _ = try? container.decode(Skip.self)
            if container.currentIndex == index { break }
        }
    }
}

/// Decodes a JSON object into `[String: Value]`, skipping values that fail.
struct LossyDictionary<Value: Decodable>: Decodable {
    var values: [String: Value] = [:]
    var failures = 0

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        for key in container.allKeys {
            if let value = try? container.decode(Value.self, forKey: key) {
                values[key.stringValue] = value
            } else {
                failures += 1
            }
        }
    }
}

private struct Skip: Decodable {
    init(from decoder: any Decoder) throws {}
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
