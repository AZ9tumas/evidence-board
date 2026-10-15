import Foundation

/// Which URLs become web cards, and how they're tidied first (DESIGN.md §7.3, §13).
public enum LinkURL {
    /// Query parameters that only track where a click came from.
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "yclid", "si", "igshid", "mc_cid", "mc_eid",
        "ref_src", "ref_url", "_hsenc", "_hsmi", "mkt_tok", "spm", "vero_id", "oly_anon_id", "oly_enc_id",
    ]

    static let commonTopLevelDomains: Set<String> = [
        "com", "org", "net", "edu", "gov", "io", "dev", "app", "co", "ai", "me", "info", "biz", "us", "uk", "de",
        "fr", "jp", "ca", "au", "nl", "se", "no", "es", "it", "ch", "in", "br", "tv", "gg", "xyz", "news", "blog",
    ]

    /// The URL in `text` when the text is a single web address, like `https://example.com/a`
    /// or `example.com/a`. Anything else, including `file:` and `javascript:` links, is `nil`.
    public static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4096,
              !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return normalize(URL(string: trimmed))
        }
        // A bare domain, maybe with a path: "www.example.com/story".
        guard !lowered.contains("://"), !lowered.hasPrefix("mailto:"), !lowered.hasPrefix("javascript:") else { return nil }
        let host = lowered.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lowered
        let hostOnly = host.split(separator: ":").first.map(String.init) ?? host
        let labels = hostOnly.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter),
              labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } })
        else { return nil }
        // "readme.md" is a file name as often as a domain: without a scheme, ask for "www.",
        // a path or a common top-level domain.
        guard hostOnly.hasPrefix("www.") || lowered.contains("/") || commonTopLevelDomains.contains(String(tld)) else { return nil }
        return normalize(URL(string: "https://" + trimmed))
    }

    /// Lowercases the scheme and host, drops the fragment, default ports and tracking
    /// parameters. Returns `nil` for anything that isn't `http` or `https` with a host.
    public static func normalize(_ url: URL?, stripTracking: Bool = true) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        components.fragment = nil
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if stripTracking, let items = components.queryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    /// The host without a leading `www.`, for display: `theverge.com`.
    public static func displayHost(of url: URL) -> String {
        let host = url.host?.lowercased() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
