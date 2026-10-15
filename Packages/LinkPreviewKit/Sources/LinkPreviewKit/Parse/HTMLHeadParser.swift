import Foundation

/// What a page's `<head>` says about it, before any choosing (DESIGN.md §7.3).
public struct HeadMetadata: Sendable, Equatable {
    /// The page address, which relative links resolve against (a `<base href>` replaces it).
    public var baseURL: URL
    /// `<title>` text.
    public var title: String?
    /// `<meta>` contents keyed by their lowercased `property`, `name` or `itemprop`, in page order.
    public var meta: [String: [String]] = [:]
    /// `og:image` entries with the `og:image:width`/`height` that followed each one.
    public var openGraphImages: [DeclaredImage] = []
    public var links: [HeadLink] = []
    public var jsonLD: [JSONLDItem] = []
    /// The charset named by `<meta charset>` or `http-equiv`, if any.
    public var charset: String?

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// The first non-empty `<meta>` value for any of `keys`, in the order given.
    public func first(_ keys: String...) -> String? {
        for key in keys {
            if let value = meta[key]?.first(where: { !$0.isEmpty }) { return value }
        }
        return nil
    }
}

/// An image URL with the size the page declares for it, if any.
public struct DeclaredImage: Sendable, Equatable {
    public var url: URL
    public var width: Int?
    public var height: Int?
    public var type: String?

    public init(url: URL, width: Int? = nil, height: Int? = nil, type: String? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.type = type
    }
}

/// A `<link>` from the head: icons, oEmbed endpoints, canonical URLs.
public struct HeadLink: Sendable, Equatable {
    /// Lowercased `rel` tokens.
    public var rel: Set<String>
    public var href: URL
    public var sizes: String?
    public var type: String?
}

/// Reads metadata out of the `<head>` of an HTML page.
///
/// It's a small tokenizer, not a full HTML parser: it walks tags until `</head>` or `<body>`,
/// skips comments, scripts and styles, and never runs anything (DESIGN.md §13). It works on
/// UTF-8 bytes, so a page cut off mid-tag is fine.
public enum HTMLHeadParser {
    /// Pages are cut off at this size before parsing.
    public static let maxBytes = 512 * 1024

    public static func parse(_ html: String, baseURL: URL) -> HeadMetadata {
        parse(bytes: Array(html.utf8), baseURL: baseURL)
    }

    public static func parse(_ data: Data, baseURL: URL) -> HeadMetadata {
        parse(bytes: Array(data.prefix(maxBytes)), baseURL: baseURL)
    }

    static func parse(bytes: [UInt8], baseURL: URL) -> HeadMetadata {
        var result = HeadMetadata(baseURL: baseURL)
        var scanner = TagScanner(bytes: bytes)
        while let tag = scanner.nextTag() {
            switch tag.name {
            case "head" where tag.isClosing, "body":
                return result
            case "base" where !tag.isClosing:
                if let href = tag.attributes["href"], let url = URL(string: href, relativeTo: result.baseURL)?.absoluteURL {
                    result.baseURL = url
                }
            case "title" where !tag.isClosing:
                let text = scanner.rawText(until: "title")
                if result.title == nil {
                    let clean = HTMLText.clean(text)
                    if !clean.isEmpty { result.title = clean }
                }
            case "meta" where !tag.isClosing:
                read(meta: tag.attributes, into: &result)
            case "link" where !tag.isClosing:
                if let link = link(from: tag.attributes, base: result.baseURL) { result.links.append(link) }
            case "script" where !tag.isClosing:
                let body = scanner.rawText(until: "script")
                if (tag.attributes["type"] ?? "").lowercased().contains("ld+json") {
                    result.jsonLD += JSONLD.items(in: body)
                }
            case "style", "noscript", "template", "svg":
                if !tag.isClosing { _ = scanner.rawText(until: tag.name) }
            default:
                break
            }
        }
        return result
    }

    private static func read(meta attributes: [String: String], into result: inout HeadMetadata) {
        if let charset = attributes["charset"] {
            result.charset = charset.lowercased()
            return
        }
        if attributes["http-equiv"]?.lowercased() == "content-type",
           let content = attributes["content"]?.lowercased(),
           let range = content.range(of: "charset=") {
            result.charset = String(content[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return
        }
        guard let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased(),
              let rawContent = attributes["content"] else { return }
        let content = HTMLText.clean(rawContent)
        result.meta[key, default: []].append(content)

        // og:image and its structured properties come as a group, in order.
        switch key {
        case "og:image", "og:image:url", "og:image:secure_url":
            guard let url = URL(string: content, relativeTo: result.baseURL)?.absoluteURL, !content.isEmpty else { return }
            if key != "og:image", let last = result.openGraphImages.last, last.width == nil,
               last.url.lastPathComponent == url.lastPathComponent {
                return // a duplicate of the image just declared
            }
            result.openGraphImages.append(DeclaredImage(url: url))
        case "og:image:width":
            if let value = Int(content), !result.openGraphImages.isEmpty { result.openGraphImages[result.openGraphImages.count - 1].width = value }
        case "og:image:height":
            if let value = Int(content), !result.openGraphImages.isEmpty { result.openGraphImages[result.openGraphImages.count - 1].height = value }
        case "og:image:type":
            if !result.openGraphImages.isEmpty { result.openGraphImages[result.openGraphImages.count - 1].type = content.lowercased() }
        default:
            break
        }
    }

    private static func link(from attributes: [String: String], base: URL) -> HeadLink? {
        guard let rel = attributes["rel"], let href = attributes["href"], !href.isEmpty,
              let url = URL(string: HTMLText.decodeEntities(href), relativeTo: base)?.absoluteURL else { return nil }
        let tokens = Set(rel.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init))
        return HeadLink(rel: tokens, href: url, sizes: attributes["sizes"]?.lowercased(), type: attributes["type"]?.lowercased())
    }
}

/// A start or end tag with its attributes (names lowercased, values entity-decoded).
struct Tag {
    var name: String
    var isClosing: Bool
    var attributes: [String: String]
}

/// Walks the tags of an HTML document as UTF-8 bytes.
struct TagScanner {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func nextTag() -> Tag? {
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "<") else {
                index += 1
                continue
            }
            if starts(with: "<!--") {
                skip(past: "-->")
                continue
            }
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") {
                skip(past: ">")
                continue
            }
            let closing = next == UInt8(ascii: "/")
            var cursor = index + (closing ? 2 : 1)
            let nameStart = cursor
            while cursor < bytes.count, Self.isNameByte(bytes[cursor]) { cursor += 1 }
            guard cursor > nameStart else {
                index += 1
                continue
            }
            let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self).lowercased()
            var attributes: [String: String] = [:]
            cursor = readAttributes(from: cursor, into: &attributes)
            index = cursor
            return Tag(name: name, isClosing: closing, attributes: attributes)
        }
        return nil
    }

    /// The raw text up to `</name>`, and moves past it.
    mutating func rawText(until name: String) -> String {
        let closing = Array("</\(name)".utf8)
        var cursor = index
        while cursor + closing.count <= bytes.count {
            if bytes[cursor] == UInt8(ascii: "<"), matches(closing, at: cursor) {
                let text = String(decoding: bytes[index..<cursor], as: UTF8.self)
                index = cursor
                skip(past: ">")
                return text
            }
            cursor += 1
        }
        let text = String(decoding: bytes[index...], as: UTF8.self)
        index = bytes.count
        return text
    }

    private func starts(with prefix: String) -> Bool {
        matches(Array(prefix.utf8), at: index)
    }

    /// Case-insensitive ASCII match.
    private func matches(_ pattern: [UInt8], at position: Int) -> Bool {
        guard position + pattern.count <= bytes.count else { return false }
        for (offset, byte) in pattern.enumerated() where Self.lower(bytes[position + offset]) != Self.lower(byte) {
            return false
        }
        return true
    }

    private mutating func skip(past terminator: String) {
        let pattern = Array(terminator.utf8)
        while index < bytes.count {
            if matches(pattern, at: index) {
                index += pattern.count
                return
            }
            index += 1
        }
    }

    private func readAttributes(from start: Int, into attributes: inout [String: String]) -> Int {
        var cursor = start
        while cursor < bytes.count {
            while cursor < bytes.count, Self.isSpace(bytes[cursor]) || bytes[cursor] == UInt8(ascii: "/") { cursor += 1 }
            guard cursor < bytes.count else { break }
            if bytes[cursor] == UInt8(ascii: ">") { return cursor + 1 }
            let nameStart = cursor
            while cursor < bytes.count, !Self.isSpace(bytes[cursor]),
                  bytes[cursor] != UInt8(ascii: "="), bytes[cursor] != UInt8(ascii: ">"), bytes[cursor] != UInt8(ascii: "/") {
                cursor += 1
            }
            let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self).lowercased()
            while cursor < bytes.count, Self.isSpace(bytes[cursor]) { cursor += 1 }
            var value = ""
            if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "=") {
                cursor += 1
                while cursor < bytes.count, Self.isSpace(bytes[cursor]) { cursor += 1 }
                if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "\"") || bytes[cursor] == UInt8(ascii: "'") {
                    let quote = bytes[cursor]
                    let valueStart = cursor + 1
                    cursor = valueStart
                    while cursor < bytes.count, bytes[cursor] != quote { cursor += 1 }
                    value = String(decoding: bytes[valueStart..<min(cursor, bytes.count)], as: UTF8.self)
                    cursor = min(cursor + 1, bytes.count)
                } else {
                    let valueStart = cursor
                    while cursor < bytes.count, !Self.isSpace(bytes[cursor]), bytes[cursor] != UInt8(ascii: ">") { cursor += 1 }
                    value = String(decoding: bytes[valueStart..<cursor], as: UTF8.self)
                }
            }
            if !name.isEmpty, attributes[name] == nil {
                attributes[name] = HTMLText.decodeEntities(value)
            }
        }
        return cursor
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39)
            || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "_")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
    }

    private static func lower(_ byte: UInt8) -> UInt8 {
        byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
    }
}

/// Entity decoding and whitespace cleanup for text taken from HTML.
public enum HTMLText {
    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "laquo": "«", "raquo": "»", "middot": "·", "bull": "•", "copy": "©", "reg": "®", "trade": "™",
        "eacute": "é", "egrave": "è", "aacute": "á", "agrave": "à", "oacute": "ó", "uuml": "ü", "ouml": "ö",
        "auml": "ä", "ntilde": "ñ", "ccedil": "ç", "szlig": "ß", "euro": "€", "pound": "£", "times": "×",
    ]

    /// Decodes entities and collapses runs of whitespace into single spaces.
    public static func clean(_ text: String) -> String {
        let decoded = decodeEntities(text)
        var result = ""
        result.reserveCapacity(decoded.count)
        var lastWasSpace = true
        for character in decoded {
            if character.isWhitespace || character == "\u{00A0}" {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let name = text[text.index(after: index)..<semicolon]
            if let decoded = decode(entity: name) {
                result += decoded
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func decode(entity name: Substring) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if name.hasPrefix("#") {
            return UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[name.lowercased()]
    }
}
