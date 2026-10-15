#if canImport(Darwin)
import Foundation
import BoardKit

/// Turns a URL into a finished preview (DESIGN.md §7.3):
///
/// normalize → disk cache → (head fetch ∥ LinkPresentation) → merge → best image and icon →
/// palette → layout variant → cache.
///
/// It never throws: a page that can't be fetched gets the fallback preview. At most four
/// pages are fetched at once, one per host.
public actor LinkPreviewService {
    public static let shared = LinkPreviewService()

    private let fetcher: PageFetcher
    private let cache: LinkPreviewCache?
    private let limiter = FetchLimiter(total: 4)
    private let useSystemMetadata: Bool

    public init(fetcher: PageFetcher = PageFetcher(), cache: LinkPreviewCache? = .standard(), useSystemMetadata: Bool = true) {
        self.fetcher = fetcher
        self.cache = cache
        self.useSystemMetadata = useSystemMetadata
    }

    /// The preview for `url`. With `refresh`, the disk cache is skipped (⌘R).
    public func preview(for url: URL, refresh: Bool = false) async -> LinkPreview {
        let url = LinkURL.normalize(url) ?? url
        if !refresh, let cached = await cache?.load(url) { return cached }
        let host = url.host ?? ""
        await limiter.acquire(host: host)
        let preview = await fetchPreview(url)
        await limiter.release(host: host)
        guard !Task.isCancelled else { return preview }
        if preview.variant != .fallback { await cache?.store(preview) }
        return preview
    }

    private func fetchPreview(_ url: URL) async -> LinkPreview {
        let fetcher = fetcher
        let wantsSystem = useSystemMetadata
        async let system = Self.systemMetadata(url, enabled: wantsSystem)
        let page = await Self.fetchHead(url, fetcher: fetcher)
        let systemResult = await system

        // A link straight to an image is its own hero.
        if let page, let mime = page.mimeType, mime.hasPrefix("image/") {
            let size = ImageProbe.pixelSize(of: page.data)
            var info = PageInfo(url: page.url)
            info.title = page.url.lastPathComponent.removingPercentEncoding ?? page.url.lastPathComponent
            return LinkPreview.make(
                from: info, image: page.data, imageSize: size, icon: nil,
                palette: size == nil ? nil : ImageProbe.palette(of: page.data)
            )
        }
        guard page != nil || systemResult != nil else { return .fallback(for: url) }

        let head = page.map { HTMLHeadParser.parse($0.data, baseURL: $0.url) } ?? HeadMetadata(baseURL: url)
        let info = MetadataMerger.merge(head, system: systemResult?.metadata, url: page?.url ?? url)

        async let icon = Self.firstImage(info.icons, fetcher: fetcher, limit: 2 * 1024 * 1024, minimumSide: 16)
        var image = await Self.firstImage(info.images, fetcher: fetcher, limit: PageFetcher.maxImageBytes, minimumSide: 1)
        if image == nil, let data = systemResult?.image, let size = ImageProbe.pixelSize(of: data) {
            image = (data, size)
        }
        let fetchedIcon = await icon
        var iconData = fetchedIcon?.data
        if iconData == nil, let data = systemResult?.icon, ImageProbe.pixelSize(of: data) != nil {
            iconData = data
        }
        let palette = image.flatMap { ImageProbe.palette(of: $0.data) } ?? iconData.flatMap(ImageProbe.palette(of:))
        return LinkPreview.make(from: info, image: image?.data, imageSize: image?.size, icon: iconData, palette: palette)
    }

    /// The page's head, trying `https` first for `http` links.
    private static func fetchHead(_ url: URL, fetcher: PageFetcher) async -> FetchedResource? {
        if url.scheme == "http", var secure = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            secure.scheme = "https"
            if let upgraded = secure.url, let page = try? await fetcher.fetchHead(upgraded) { return page }
        }
        return try? await fetcher.fetchHead(url)
    }

    /// The first of the first three candidates that downloads and decodes.
    private static func firstImage(
        _ candidates: [DeclaredImage], fetcher: PageFetcher, limit: Int, minimumSide: Int
    ) async -> (data: Data, size: PixelSize)? {
        for candidate in candidates.prefix(3) {
            guard !Task.isCancelled else { return nil }
            guard let resource = try? await fetcher.fetchData(candidate.url, limit: limit),
                  let size = ImageProbe.pixelSize(of: resource.data),
                  size.width >= minimumSide, size.height >= minimumSide else { continue }
            return (resource.data, size)
        }
        return nil
    }

    private static func systemMetadata(_ url: URL, enabled: Bool) async -> SystemLinkResult? {
        guard enabled else { return nil }
        #if canImport(LinkPresentation)
        return await SystemLinkMetadata.fetch(url)
        #else
        return nil
        #endif
    }
}
#endif
