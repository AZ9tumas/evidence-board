import Foundation

/// Previews fetched before, on disk: a JSON file per URL plus its image and icon, kept for
/// 30 days and trimmed to 500 MB, oldest-used first (DESIGN.md §7.6).
public actor LinkPreviewCache {
    public let directory: URL
    let maxAge: TimeInterval
    let maxBytes: Int
    private var storesSincePrune = 0

    public init(directory: URL, maxAge: TimeInterval = 30 * 86_400, maxBytes: Int = 500 * 1024 * 1024) {
        self.directory = directory
        self.maxAge = maxAge
        self.maxBytes = maxBytes
    }

    /// `~/Library/Caches/<bundle id>/LinkPreviews` (inside the sandbox container).
    public static func standard() -> LinkPreviewCache? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let bundle = Bundle.main.bundleIdentifier ?? "EvidenceBoard"
        return LinkPreviewCache(directory: caches.appendingPathComponent(bundle).appendingPathComponent("LinkPreviews"))
    }

    public func load(_ url: URL, now: Date = .now) -> LinkPreview? {
        let key = Self.key(for: url)
        let jsonURL = file(key, "json")
        guard let data = try? Data(contentsOf: jsonURL),
              let entry = try? Self.decoder.decode(CachedPreview.self, from: data),
              entry.url == url, now.timeIntervalSince(entry.fetchedAt) < maxAge else { return nil }
        // Touch it, so pruning keeps what's used.
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: jsonURL.path)
        return LinkPreview(
            url: entry.url, fetchedAt: entry.fetchedAt, variant: entry.variant, title: entry.title,
            pageDescription: entry.pageDescription, siteName: entry.siteName, author: entry.author,
            publishedAt: entry.publishedAt, duration: entry.duration, palette: entry.palette,
            image: entry.hasImage ? try? Data(contentsOf: file(key, "image")) : nil,
            imageSize: entry.imageSize,
            icon: entry.hasIcon ? try? Data(contentsOf: file(key, "icon")) : nil
        )
    }

    public func store(_ preview: LinkPreview) {
        let key = Self.key(for: preview.url)
        let entry = CachedPreview(
            url: preview.url, fetchedAt: preview.fetchedAt, variant: preview.variant, title: preview.title,
            pageDescription: preview.pageDescription, siteName: preview.siteName, author: preview.author,
            publishedAt: preview.publishedAt, duration: preview.duration, palette: preview.palette,
            imageSize: preview.imageSize, hasImage: preview.image != nil, hasIcon: preview.icon != nil
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let image = preview.image { try image.write(to: file(key, "image"), options: .atomic) }
            if let icon = preview.icon { try icon.write(to: file(key, "icon"), options: .atomic) }
            try Self.encoder.encode(entry).write(to: file(key, "json"), options: .atomic)
        } catch {
            return
        }
        storesSincePrune += 1
        if storesSincePrune >= 20 {
            storesSincePrune = 0
            prune()
        }
    }

    /// Deletes expired entries, then the least recently used until under the size cap.
    public func prune(now: Date = .now) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var groups: [String: (modified: Date, bytes: Int, files: [URL])] = [:]
        for file in files {
            let key = file.deletingPathExtension().lastPathComponent
            let values = try? file.resourceValues(forKeys: Set(keys))
            var group = groups[key] ?? (.distantPast, 0, [])
            group.bytes += values?.fileSize ?? 0
            group.files.append(file)
            if file.pathExtension == "json" { group.modified = values?.contentModificationDate ?? .distantPast }
            groups[key] = group
        }
        var total = groups.values.reduce(0) { $0 + $1.bytes }
        for (_, group) in groups.sorted(by: { $0.value.modified < $1.value.modified }) {
            guard now.timeIntervalSince(group.modified) >= maxAge || total > maxBytes else { break }
            for file in group.files { try? manager.removeItem(at: file) }
            total -= group.bytes
        }
    }

    private func file(_ key: String, _ ext: String) -> URL {
        directory.appendingPathComponent("\(key).\(ext)")
    }

    /// FNV-1a of the URL, as 16 hex digits.
    static func key(for url: URL) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16).leftPadded(to: 16)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}

extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
