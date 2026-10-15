#if canImport(Darwin)
import Foundation

/// The bytes of a page's head (or of an image), and what the server said about them.
public struct FetchedResource: Sendable {
    public var url: URL
    public var mimeType: String?
    public var data: Data
}

public enum FetchError: Error, Sendable {
    case badStatus(Int)
    case tooLarge
    case timedOut
}

/// Downloads page heads and images with `URLSession` (DESIGN.md §7.3): a desktop Safari user
/// agent, a 10 s timeout, no cookies, and hard caps on size.
public struct PageFetcher: Sendable {
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    public static let timeout: TimeInterval = 10
    public static let maxImageBytes = 15 * 1024 * 1024

    let session: URLSession

    public init(session: URLSession = PageFetcher.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ", "),
        ]
        return URLSession(configuration: configuration)
    }

    /// The page up to `</head>` (or 512 KB), converted to UTF-8 so the parser can read it.
    /// Non-HTML responses come back whole, up to the image cap, so a link straight to an
    /// image still makes a card.
    public func fetchHead(_ url: URL) async throws -> FetchedResource {
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        try Self.check(response)
        let mime = response.mimeType?.lowercased()
        let isHTML = mime == nil || mime!.contains("html") || mime!.contains("xml")
        let limit = isHTML ? HTMLHeadParser.maxBytes : Self.maxImageBytes
        var data = Data()
        data.reserveCapacity(64 * 1024)
        let marker = Array("</head".utf8)
        var checkedUpTo = 0
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                if !isHTML { throw FetchError.tooLarge }
                break
            }
            if isHTML, data.count - checkedUpTo >= 2048 {
                if Self.containsCaseInsensitive(data, marker, from: max(checkedUpTo - marker.count, 0)) { break }
                checkedUpTo = data.count
            }
        }
        if isHTML {
            data = Self.utf8(data, declared: response.textEncodingName)
        }
        return FetchedResource(url: response.url ?? url, mimeType: mime, data: data)
    }

    /// An image, up to the size cap.
    public func fetchData(_ url: URL, limit: Int = PageFetcher.maxImageBytes) async throws -> FetchedResource {
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.setValue("image/avif,image/webp,image/png,image/*;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        try Self.check(response)
        if response.expectedContentLength > Int64(limit) { throw FetchError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw FetchError.tooLarge }
        }
        return FetchedResource(url: response.url ?? url, mimeType: response.mimeType?.lowercased(), data: data)
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.badStatus(http.statusCode)
        }
    }

    static func containsCaseInsensitive(_ data: Data, _ pattern: [UInt8], from start: Int) -> Bool {
        let bytes = [UInt8](data[data.startIndex.advanced(by: start)...])
        guard bytes.count >= pattern.count else { return false }
        outer: for index in 0...(bytes.count - pattern.count) {
            for (offset, byte) in pattern.enumerated() {
                var candidate = bytes[index + offset]
                if candidate >= 0x41 && candidate <= 0x5A { candidate += 0x20 }
                if candidate != byte { continue outer }
            }
            return true
        }
        return false
    }

    /// Re-encodes a page in another charset (from the header or a `<meta charset>`) as UTF-8.
    static func utf8(_ data: Data, declared: String?) -> Data {
        let sniffed = HTMLHeadParser.parse(Data(data.prefix(4096)), baseURL: URL(string: "about:blank")!).charset
        guard let name = (declared ?? sniffed)?.lowercased(), name != "utf-8", name != "utf8" else { return data }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return data }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        guard let text = String(data: data, encoding: encoding) else { return data }
        return Data(text.utf8)
    }
}
#endif
