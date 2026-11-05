import Foundation

// MARK: - Text

public struct TextPayload: Sendable, Equatable, Codable {
    public static let fontSizeRange: ClosedRange<Double> = 8...96
    public var content: String
    public var style: TextCardStyle
    public var alignment: TextCardAlignment
    public var autoHeight: Bool
    /// Nil follows the card style, preserving the appearance of older boards.
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool

    public init(
        content: String,
        style: TextCardStyle = .note,
        alignment: TextCardAlignment = .leading,
        autoHeight: Bool = true,
        fontSize: Double? = nil,
        bold: Bool? = nil,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false
    ) {
        self.content = content
        self.style = style
        self.alignment = alignment
        self.autoHeight = autoHeight
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decode(String.self, forKey: .content)
        style = try c.decodeIfPresent(TextCardStyle.self, forKey: .style) ?? .note
        alignment = try c.decodeIfPresent(TextCardAlignment.self, forKey: .alignment) ?? .leading
        autoHeight = try c.decodeIfPresent(Bool.self, forKey: .autoHeight) ?? true
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold)
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        strikethrough = try c.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
    }

    public var resolvedFontSize: Double {
        guard let fontSize, fontSize.isFinite else { return style.defaultFontSize }
        return min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    public func isEnabled(_ format: TextFormat) -> Bool {
        switch format {
        case .bold: bold ?? (style == .headline)
        case .italic: italic
        case .underline: underline
        case .strikethrough: strikethrough
        }
    }

    public mutating func set(_ format: TextFormat, enabled: Bool) {
        switch format {
        case .bold: bold = enabled
        case .italic: italic = enabled
        case .underline: underline = enabled
        case .strikethrough: strikethrough = enabled
        }
    }

    public mutating func resetFormatting() {
        style = .note
        alignment = .leading
        fontSize = nil
        bold = nil
        italic = false
        underline = false
        strikethrough = false
    }
}

public enum TextFormat: String, Sendable, CaseIterable {
    case bold, italic, underline, strikethrough
}

public enum TextCardStyle: String, Sendable, CaseIterable, DefaultedEnum {
    case note, headline, typewriter
    public static let unknownValue: TextCardStyle = .note

    public var defaultFontSize: Double {
        switch self {
        case .note: 15
        case .headline: 28
        case .typewriter: 14
        }
    }
}

public enum TextCardAlignment: String, Sendable, CaseIterable, DefaultedEnum {
    case leading, center, trailing
    public static let unknownValue: TextCardAlignment = .leading
}

// MARK: - Image

public struct ImagePayload: Sendable, Equatable, Codable {
    public var asset: AssetID
    public var caption: String?
    public var frameStyle: ImageFrameStyle
    /// Normalized (0...1) crop rectangle, if any.
    public var crop: Rect?

    public init(asset: AssetID, caption: String? = nil, frameStyle: ImageFrameStyle = .polaroid, crop: Rect? = nil) {
        self.asset = asset
        self.caption = caption
        self.frameStyle = frameStyle
        self.crop = crop
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asset = try c.decode(AssetID.self, forKey: .asset)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        frameStyle = try c.decodeIfPresent(ImageFrameStyle.self, forKey: .frameStyle) ?? .polaroid
        crop = try c.decodeIfPresent(Rect.self, forKey: .crop)
    }
}

public enum ImageFrameStyle: String, Sendable, CaseIterable, DefaultedEnum {
    case polaroid, borderless, photo
    public static let unknownValue: ImageFrameStyle = .polaroid
}

// MARK: - Web

public struct WebPayload: Sendable, Equatable, Codable {
    public var url: URL
    /// The saved preview. `nil` until the page has been fetched once.
    public var snapshot: LinkSnapshot?

    public init(url: URL, snapshot: LinkSnapshot? = nil) {
        self.url = url
        self.snapshot = snapshot
    }
}

/// Everything needed to draw a web card offline.
public struct LinkSnapshot: Sendable, Equatable, Codable {
    public var fetchedAt: Date
    public var variant: LinkVariant
    public var title: String?
    public var pageDescription: String?
    public var siteName: String?
    public var author: String?
    public var publishedAt: Date?
    /// Seconds, for video pages.
    public var mediaDuration: Double?
    public var image: AssetID?
    public var icon: AssetID?
    public var palette: LinkPalette?

    public init(
        fetchedAt: Date,
        variant: LinkVariant,
        title: String? = nil,
        pageDescription: String? = nil,
        siteName: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        mediaDuration: Double? = nil,
        image: AssetID? = nil,
        icon: AssetID? = nil,
        palette: LinkPalette? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.variant = variant
        self.title = title
        self.pageDescription = pageDescription
        self.siteName = siteName
        self.author = author
        self.publishedAt = publishedAt
        self.mediaDuration = mediaDuration
        self.image = image
        self.icon = icon
        self.palette = palette
    }

    enum CodingKeys: String, CodingKey {
        case fetchedAt, variant, title, siteName, author, publishedAt, mediaDuration, image, icon, palette
        case pageDescription = "description"
    }
}

public enum LinkVariant: String, Sendable, CaseIterable, DefaultedEnum {
    case hero, portrait, media, social, article, compact, fallback
    public static let unknownValue: LinkVariant = .fallback
}

/// Five role-based swatches taken from the page's image, stored as `#RRGGBB`.
public struct LinkPalette: Sendable, Equatable, Codable {
    public var vibrant: String
    public var muted: String
    public var darkVibrant: String
    public var darkMuted: String
    public var light: String

    public init(vibrant: String, muted: String, darkVibrant: String, darkMuted: String, light: String) {
        self.vibrant = vibrant
        self.muted = muted
        self.darkVibrant = darkVibrant
        self.darkMuted = darkMuted
        self.light = light
    }
}
