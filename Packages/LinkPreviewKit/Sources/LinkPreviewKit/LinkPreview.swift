import Foundation
import BoardKit

/// A finished preview: the text, the chosen layout, the palette and the raw image bytes.
/// The canvas turns the bytes into board assets and stores the rest as a `LinkSnapshot`.
public struct LinkPreview: Sendable, Equatable {
    public var url: URL
    public var fetchedAt: Date
    public var variant: LinkVariant
    public var title: String?
    public var pageDescription: String?
    public var siteName: String?
    public var author: String?
    public var publishedAt: Date?
    public var duration: Double?
    public var palette: LinkPalette
    /// Encoded hero (or poster, or avatar) image, as downloaded.
    public var image: Data?
    public var imageSize: PixelSize?
    /// Encoded site icon, as downloaded.
    public var icon: Data?

    public init(
        url: URL, fetchedAt: Date, variant: LinkVariant, title: String? = nil, pageDescription: String? = nil,
        siteName: String? = nil, author: String? = nil, publishedAt: Date? = nil, duration: Double? = nil,
        palette: LinkPalette, image: Data? = nil, imageSize: PixelSize? = nil, icon: Data? = nil
    ) {
        self.url = url
        self.fetchedAt = fetchedAt
        self.variant = variant
        self.title = title
        self.pageDescription = pageDescription
        self.siteName = siteName
        self.author = author
        self.publishedAt = publishedAt
        self.duration = duration
        self.palette = palette
        self.image = image
        self.imageSize = imageSize
        self.icon = icon
    }

    /// What a card shows when the page couldn't be fetched: the host as its title and a
    /// gradient made from the domain.
    public static func fallback(for url: URL, at date: Date = .now) -> LinkPreview {
        let host = LinkURL.displayHost(of: url)
        return LinkPreview(url: url, fetchedAt: date, variant: .fallback, title: host, palette: PaletteExtractor.palette(forDomain: host))
    }

    /// The preview built from a merged page and whatever images were found.
    public static func make(
        from page: PageInfo, image: Data?, imageSize: PixelSize?, icon: Data?, palette: LinkPalette?, at date: Date = .now
    ) -> LinkPreview {
        let host = LinkURL.displayHost(of: page.url)
        let resolvedPalette = palette
            ?? page.themeColor.flatMap(PaletteExtractor.palette(around:))
            ?? PaletteExtractor.palette(forDomain: host)
        return LinkPreview(
            url: page.url,
            fetchedAt: date,
            variant: VariantRules.variant(for: page.kind, image: imageSize),
            title: page.title ?? host,
            pageDescription: page.description,
            siteName: page.siteName,
            author: page.author,
            publishedAt: page.publishedAt,
            duration: page.duration,
            palette: resolvedPalette,
            image: imageSize == nil ? nil : image,
            imageSize: imageSize,
            icon: icon
        )
    }
}

/// The JSON part of a cached preview; images live in files next to it.
struct CachedPreview: Codable {
    var url: URL
    var fetchedAt: Date
    var variant: LinkVariant
    var title: String?
    var pageDescription: String?
    var siteName: String?
    var author: String?
    var publishedAt: Date?
    var duration: Double?
    var palette: LinkPalette
    var imageSize: PixelSize?
    var hasImage: Bool
    var hasIcon: Bool
}
