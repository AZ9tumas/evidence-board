import Foundation

/// The parts of a schema.org JSON-LD object that a preview can use.
public struct JSONLDItem: Sendable, Equatable {
    /// `@type` values, like `NewsArticle` or `VideoObject`.
    public var types: Set<String> = []
    public var headline: String?
    public var description: String?
    public var author: String?
    public var publisher: String?
    public var datePublished: Date?
    public var images: [URL] = []
    /// Seconds, from an ISO 8601 duration like `PT4M13S`.
    public var duration: Double?

    public init() {}

    public var isArticle: Bool {
        !types.isDisjoint(with: ["Article", "NewsArticle", "BlogPosting", "Report", "ScholarlyArticle", "TechArticle", "AnalysisNewsArticle", "OpinionNewsArticle", "ReportageNewsArticle"])
    }

    public var isVideo: Bool {
        types.contains("VideoObject") || types.contains("Movie") || types.contains("TVEpisode")
    }

    public var isSocialPost: Bool {
        types.contains("SocialMediaPosting") || types.contains("DiscussionForumPosting")
    }
}

enum JSONLD {
    /// Every typed object in a `<script type="application/ld+json">` block, including the
    /// ones inside `@graph`. Broken JSON yields nothing.
    static func items(in script: String) -> [JSONLDItem] {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
        guard let data = trimmed.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        var found: [JSONLDItem] = []
        collect(root, into: &found, depth: 0)
        return found
    }

    private static func collect(_ value: Any, into found: inout [JSONLDItem], depth: Int) {
        guard depth < 6 else { return }
        if let array = value as? [Any] {
            for element in array { collect(element, into: &found, depth: depth + 1) }
        } else if let object = value as? [String: Any] {
            if let graph = object["@graph"] { collect(graph, into: &found, depth: depth + 1) }
            if let item = item(from: object) { found.append(item) }
        }
    }

    private static func item(from object: [String: Any]) -> JSONLDItem? {
        let types = strings(object["@type"])
        guard !types.isEmpty else { return nil }
        var item = JSONLDItem()
        item.types = Set(types)
        item.headline = text(object["headline"]) ?? text(object["name"])
        item.description = text(object["description"])
        item.author = name(of: object["author"]) ?? name(of: object["creator"])
        item.publisher = name(of: object["publisher"])
        item.datePublished = (text(object["datePublished"]) ?? text(object["uploadDate"]) ?? text(object["dateCreated"])).flatMap(ISODate.parse)
        item.images = urls(object["image"]) + urls(object["thumbnailUrl"])
        item.duration = text(object["duration"]).flatMap(ISODuration.seconds)
        return item
    }

    private static func strings(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.compactMap { $0 as? String } }
        return []
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String) ?? (value as? [Any])?.first as? String else { return nil }
        let clean = HTMLText.clean(string)
        return clean.isEmpty ? nil : clean
    }

    /// A person or organization: a string, `{"name": …}`, or a list of either.
    private static func name(of value: Any?) -> String? {
        if let string = value as? String { return string.hasPrefix("http") ? nil : text(string) }
        if let object = value as? [String: Any] { return text(object["name"]) }
        if let array = value as? [Any] {
            let names = array.compactMap { name(of: $0) }
            return names.isEmpty ? nil : names.prefix(2).joined(separator: ", ")
        }
        return nil
    }

    private static func urls(_ value: Any?) -> [URL] {
        if let string = value as? String { return URL(string: string).map { [$0] } ?? [] }
        if let object = value as? [String: Any] {
            return (text(object["url"]) ?? text(object["contentUrl"])).flatMap { URL(string: $0) }.map { [$0] } ?? []
        }
        if let array = value as? [Any] { return array.flatMap { urls($0) } }
        return []
    }
}

/// ISO 8601 dates as pages write them: with or without time, fractional seconds or zone.
public enum ISODate {
    public static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: trimmed) { return date }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: trimmed) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mmZ", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}

/// ISO 8601 durations such as `PT1H2M3S` or `P0DT4M`.
public enum ISODuration {
    public static func seconds(_ text: String) -> Double? {
        let upper = text.uppercased()
        guard upper.hasPrefix("P") else { return Double(text) }
        var total = 0.0
        var number = ""
        var inTime = false
        var sawUnit = false
        for character in upper.dropFirst() {
            if character == "T" {
                inTime = true
            } else if character.isNumber || character == "." {
                number.append(character)
            } else {
                guard let value = Double(number) else { return nil }
                switch (character, inTime) {
                case ("D", false): total += value * 86_400
                case ("H", true): total += value * 3_600
                case ("M", true): total += value * 60
                case ("S", true): total += value
                case ("W", false): total += value * 604_800
                default: return nil
                }
                number = ""
                sawUnit = true
            }
        }
        return sawUnit && number.isEmpty ? total : nil
    }
}
