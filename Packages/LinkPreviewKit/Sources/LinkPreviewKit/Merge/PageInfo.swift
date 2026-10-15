import Foundation
import BoardKit

/// Everything known about a page after merging all sources, before images are fetched.
public struct PageInfo: Sendable, Equatable {
    public var url: URL
    public var title: String?
    public var description: String?
    public var siteName: String?
    public var author: String?
    public var publishedAt: Date?
    /// Seconds, for video pages.
    public var duration: Double?
    public var themeColor: String?
    /// Image candidates, best first.
    public var images: [DeclaredImage] = []
    /// Icon candidates, best first.
    public var icons: [DeclaredImage] = []
    public var kind: Kind = .page

    public enum Kind: Sendable, Equatable {
        case page, article, video, social
    }

    public init(url: URL) {
        self.url = url
    }
}

/// Results from the system's link metadata fetcher (LinkPresentation), used to fill gaps.
public struct SystemMetadata: Sendable, Equatable {
    public var title: String?
    public var hasVideo = false

    public init(title: String? = nil, hasVideo: Bool = false) {
        self.title = title
        self.hasVideo = hasVideo
    }
}

/// Picks the best title, description, image and icon from everything a page offers
/// (DESIGN.md §7.3).
public enum MetadataMerger {
    static let socialHosts = [
        "twitter.com", "x.com", "bsky.app", "threads.net", "threads.com", "reddit.com", "old.reddit.com",
        "mastodon.social", "mstdn.social", "fosstodon.org", "hachyderm.io", "mas.to", "infosec.exchange",
        "instagram.com", "facebook.com", "linkedin.com", "tumblr.com",
    ]
    static let videoHosts = ["youtube.com", "youtu.be", "m.youtube.com", "vimeo.com", "twitch.tv", "tiktok.com", "dailymotion.com", "loom.com"]

    public static func merge(_ head: HeadMetadata, system: SystemMetadata? = nil, url: URL) -> PageInfo {
        var info = PageInfo(url: url)
        let ld = head.jsonLD
        let primary = ld.first(where: { $0.isArticle || $0.isVideo || $0.isSocialPost }) ?? ld.first

        info.siteName = head.first("og:site_name", "application-name", "apple-mobile-web-app-title", "al:ios:app_name")
            ?? ld.compactMap(\.publisher).first
        info.title = head.first("og:title", "twitter:title")
            ?? primary?.headline
            ?? system?.title
            ?? head.title
        info.title = info.title.map { tidyTitle($0, siteName: info.siteName, host: LinkURL.displayHost(of: url)) }
        info.description = head.first("og:description", "twitter:description", "description")
            ?? primary?.description
        info.author = authorName(head.first("author", "article:author", "parsely-author", "sailthru.author"))
            ?? primary?.author
            ?? head.first("twitter:creator")
        info.publishedAt = head.first("article:published_time", "og:published_time", "datepublished", "date", "pubdate", "parsely-pub-date")
            .flatMap(ISODate.parse)
            ?? primary?.datePublished
        info.duration = head.first("og:video:duration", "video:duration", "duration").flatMap { Double($0) ?? ISODuration.seconds($0) }
            ?? ld.compactMap(\.duration).first
        info.themeColor = head.first("theme-color", "msapplication-tilecolor").flatMap(ColorText.hex)

        info.images = rankedImages(head, ld: ld)
        info.icons = rankedIcons(head)

        let host = LinkURL.displayHost(of: url)
        let ogType = head.first("og:type")?.lowercased() ?? ""
        if matches(host, socialHosts) || ld.contains(where: \.isSocialPost) {
            info.kind = .social
        } else if ogType.hasPrefix("video") || ld.contains(where: \.isVideo) || matches(host, videoHosts) || system?.hasVideo == true
                    || head.first("og:video", "og:video:url", "og:video:secure_url") != nil {
            info.kind = .video
        } else if ld.contains(where: \.isArticle) || (ogType == "article" && (info.author != nil || info.publishedAt != nil)) {
            info.kind = .article
        }
        return info
    }

    static func matches(_ host: String, _ list: [String]) -> Bool {
        list.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Drops a trailing " | Site Name" (or " - ", " — ", " · ") that repeats the site's name.
    static func tidyTitle(_ title: String, siteName: String?, host: String) -> String {
        // The site's own name, its host, and the host's main label ("wikipedia" for en.wikipedia.org).
        let labels = host.split(separator: ".").map(String.init)
        let mainLabel = labels.count >= 2 ? labels[labels.count - 2] : labels.first
        let names = [siteName, host, labels.first, mainLabel].compactMap { $0?.lowercased() }
        for separator in [" | ", " - ", " — ", " – ", " · ", " :: "] {
            guard let range = title.range(of: separator, options: .backwards) else { continue }
            let tail = title[range.upperBound...].lowercased()
            let head = title[..<range.lowerBound]
            if head.count >= 8, names.contains(where: { tail == $0 || tail.replacingOccurrences(of: " ", with: "") == $0.replacingOccurrences(of: " ", with: "") }) {
                return String(head)
            }
        }
        return title
    }

    /// Bylines are sometimes profile URLs; those aren't names.
    static func authorName(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.lowercased().hasPrefix("http") else { return nil }
        return value
    }

    /// Scored by declared size (600 px or more is good), shape (closest to 1.91:1) and
    /// format. SVG can't be shown and is dropped.
    static func rankedImages(_ head: HeadMetadata, ld: [JSONLDItem]) -> [DeclaredImage] {
        var candidates: [(image: DeclaredImage, order: Int)] = []
        func add(_ image: DeclaredImage) {
            guard !isSVG(image), !candidates.contains(where: { $0.image.url == image.url }) else { return }
            candidates.append((image, candidates.count))
        }
        head.openGraphImages.forEach(add)
        for key in ["twitter:image", "twitter:image:src"] {
            for value in head.meta[key] ?? [] {
                if let url = URL(string: value, relativeTo: head.baseURL)?.absoluteURL { add(DeclaredImage(url: url)) }
            }
        }
        for url in ld.flatMap(\.images) { add(DeclaredImage(url: url)) }
        for link in head.links where link.rel.contains("image_src") { add(DeclaredImage(url: link.href)) }
        return candidates
            .sorted { score($0.image) - Double($0.order) * 0.05 > score($1.image) - Double($1.order) * 0.05 }
            .map(\.image)
    }

    static func score(_ image: DeclaredImage) -> Double {
        var score = 0.0
        if let width = image.width {
            score += width >= 600 ? 2 : width < 200 ? -2 : 0
            if let height = image.height, height > 0 {
                let aspect = Double(width) / Double(height)
                score += 1 - min(abs(log(aspect / 1.91)), 1)
            }
        }
        let path = image.url.path.lowercased()
        if path.contains("logo") || path.contains("favicon") || path.contains("sprite") { score -= 1.5 }
        return score
    }

    static func isSVG(_ image: DeclaredImage) -> Bool {
        image.type?.contains("svg") == true || image.url.pathExtension.lowercased() == "svg"
    }

    /// apple-touch-icon, then other icons by declared size, then `/favicon.ico`.
    static func rankedIcons(_ head: HeadMetadata) -> [DeclaredImage] {
        var icons: [(icon: DeclaredImage, score: Int)] = []
        for link in head.links {
            let touch = link.rel.contains("apple-touch-icon") || link.rel.contains("apple-touch-icon-precomposed")
            guard touch || link.rel.contains("icon") else { continue }
            let icon = DeclaredImage(url: link.href, type: link.type)
            guard !isSVG(icon), !link.rel.contains("mask-icon") else { continue }
            let size = declaredSize(link.sizes) ?? (touch ? 180 : 32)
            icons.append((icon, size + (touch ? 1000 : 0)))
        }
        var ranked = icons.sorted { $0.score > $1.score }.map(\.icon)
        if let root = URL(string: "/favicon.ico", relativeTo: head.baseURL)?.absoluteURL, !ranked.contains(where: { $0.url == root }) {
            ranked.append(DeclaredImage(url: root))
        }
        return ranked
    }

    /// The largest side in a `sizes` attribute like `"32x32 192x192"`.
    static func declaredSize(_ sizes: String?) -> Int? {
        guard let sizes else { return nil }
        return sizes.split(separator: " ").compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max()
    }
}

/// CSS-ish color text to `#RRGGBB`.
public enum ColorText {
    public static func hex(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") {
            let digits = value.dropFirst()
            guard digits.allSatisfy(\.isHexDigit) else { return nil }
            if digits.count == 3 { return "#" + digits.map { "\($0)\($0)" }.joined().uppercased() }
            if digits.count == 6 || digits.count == 8 { return "#" + digits.prefix(6).uppercased() }
            return nil
        }
        if value.hasPrefix("rgb") {
            let numbers = value.drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" })
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0) }
            guard numbers.count >= 3 else { return nil }
            return String(format: "#%02X%02X%02X", Int(min(max(numbers[0], 0), 255)), Int(min(max(numbers[1], 0), 255)), Int(min(max(numbers[2], 0), 255)))
        }
        return nil
    }
}
