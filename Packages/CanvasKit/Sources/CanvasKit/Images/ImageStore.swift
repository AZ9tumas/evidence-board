import Foundation
import ImageIO
import BoardKit

/// A decoded image that can cross from the decoding thread to the main actor. `CGImage` is
/// immutable, so sharing it is safe.
struct DecodedImage: @unchecked Sendable {
    let image: CGImage
}

/// Decodes asset images at the size the canvas needs and keeps a bounded cache of them
/// (DESIGN.md §10.5).
///
/// Decoding runs on background threads, a few at a time. Each image is decoded with ImageIO's
/// thumbnail API straight to the needed size, so a 4096-pixel photo shown at 300 points never
/// becomes a full-size bitmap. Sizes are bucketed to powers of two, and any cached size at
/// least as large as the request is reused.
@MainActor
final class ImageStore {
    private struct Entry {
        let image: CGImage
        let cost: Int
        var lastUse: UInt64
    }

    static let maxConcurrentDecodes = 3

    /// Upper bound on decoded bitmap memory, in bytes.
    let budget: Int
    private(set) var totalCost = 0
    private var entries: [AssetID: [Int: Entry]] = [:]
    private var clock: UInt64 = 0

    private struct Request: Hashable {
        let asset: AssetID
        let longSide: Int
    }

    private var waiting: [Request: [(CGImage) -> Void]] = [:]
    private var queue: [(Request, String)] = []
    private var running = 0

    init(budget: Int = ImageStore.defaultBudget) {
        self.budget = budget
    }

    /// About a tenth of physical memory, between 256 MB and 1.5 GB.
    static var defaultBudget: Int {
        let tenth = Int(ProcessInfo.processInfo.physicalMemory / 10)
        return min(max(tenth, 256 << 20), 1536 << 20)
    }

    /// The smallest cached decode of `asset` with at least `longSide` pixels, if any.
    func cachedImage(asset: AssetID, longSide: Int) -> CGImage? {
        guard let sizes = entries[asset],
              let size = sizes.keys.filter({ $0 >= longSide }).min(),
              var entry = sizes[size] else { return nil }
        clock += 1
        entry.lastUse = clock
        entries[asset]?[size] = entry
        return entry.image
    }

    /// Calls `completion` with `asset` decoded to about `longSide` pixels: right away if it's
    /// cached, otherwise once a background decode finishes. Failed decodes never call back.
    func load(asset: AssetID, base64: String, longSide: Int, completion: @escaping (CGImage) -> Void) {
        let longSide = ImageCardLayout.bucket(longSide)
        if let image = cachedImage(asset: asset, longSide: longSide) {
            completion(image)
            return
        }
        let request = Request(asset: asset, longSide: longSide)
        if waiting[request] != nil {
            waiting[request]?.append(completion)
            return
        }
        waiting[request] = [completion]
        queue.append((request, base64))
        pump()
    }

    private func pump() {
        while running < Self.maxConcurrentDecodes, !queue.isEmpty {
            let (request, base64) = queue.removeFirst()
            running += 1
            Task { [weak self] in
                let decoded = await Task.detached(priority: .userInitiated) {
                    Self.decode(base64: base64, maxLongSide: request.longSide)
                }.value
                self?.finish(request, decoded?.image)
            }
        }
    }

    private func finish(_ request: Request, _ image: CGImage?) {
        running -= 1
        let callbacks = waiting.removeValue(forKey: request) ?? []
        if let image {
            insert(image, for: request)
            for callback in callbacks { callback(image) }
        }
        pump()
    }

    private func insert(_ image: CGImage, for request: Request) {
        clock += 1
        let cost = image.bytesPerRow * image.height
        if let old = entries[request.asset]?[request.longSide] { totalCost -= old.cost }
        entries[request.asset, default: [:]][request.longSide] = Entry(image: image, cost: cost, lastUse: clock)
        totalCost += cost
        evictIfNeeded()
    }

    /// Drops the least recently used decodes until the cache fits its budget. Images still on
    /// screen keep their own reference, so this only frees memory nobody is looking at.
    private func evictIfNeeded() {
        while totalCost > budget {
            var oldest: (asset: AssetID, size: Int, use: UInt64)?
            for (asset, sizes) in entries {
                for (size, entry) in sizes where entry.lastUse < (oldest?.use ?? .max) {
                    oldest = (asset, size, entry.lastUse)
                }
            }
            guard let oldest, let entry = entries[oldest.asset]?.removeValue(forKey: oldest.size) else { return }
            if entries[oldest.asset]?.isEmpty == true { entries[oldest.asset] = nil }
            totalCost -= entry.cost
        }
    }

    /// Decodes base64 image bytes straight to at most `maxLongSide` pixels on the long side,
    /// with the image's orientation applied.
    nonisolated static func decode(base64: String, maxLongSide: Int) -> DecodedImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(DecodedImage.init)
    }
}
