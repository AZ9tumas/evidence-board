import AppKit
import BoardKit
import LinkPreviewKit

/// What a web card shows, gathered from its payload and the board's assets.
struct WebCardContent: Equatable {
    var variant: LinkVariant
    /// The preview is being fetched: show the skeleton.
    var isLoading: Bool
    var title: String
    var pageDescription: String?
    var siteName: String?
    var domain: String
    var author: String?
    var publishedAt: Date?
    var duration: Double?
    var palette: LinkPalette
    /// Width over height of the snapshot's image, when it has one.
    var imageAspect: CGFloat?
    var hasIcon: Bool

    init(payload: WebPayload, assets: [AssetID: Asset], isLoading: Bool) {
        let host = payload.url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? payload.url.absoluteString
        domain = host
        self.isLoading = isLoading && payload.snapshot == nil
        guard let snapshot = payload.snapshot else {
            variant = self.isLoading ? .hero : .fallback
            title = host
            palette = PaletteExtractor.palette(forDomain: host)
            hasIcon = false
            return
        }
        variant = snapshot.variant
        title = (snapshot.title?.isEmpty == false ? snapshot.title : nil) ?? host
        pageDescription = snapshot.pageDescription?.isEmpty == false ? snapshot.pageDescription : nil
        siteName = snapshot.siteName
        author = snapshot.author
        publishedAt = snapshot.publishedAt
        duration = snapshot.mediaDuration
        palette = snapshot.palette ?? PaletteExtractor.palette(forDomain: host)
        if let id = snapshot.image, let asset = assets[id] {
            if let width = asset.pixelWidth, let height = asset.pixelHeight, width > 0, height > 0 {
                imageAspect = CGFloat(width) / CGFloat(height)
            } else {
                imageAspect = 16.0 / 9.0
            }
        }
        hasIcon = snapshot.icon.map { assets[$0] != nil } ?? false
        // A variant that needs an image falls back to compact when the image is missing.
        if imageAspect == nil, [.hero, .article, .media, .portrait].contains(variant) {
            variant = .compact
        }
    }

    /// Social posts use a square-ish, smallish image as the author's avatar.
    var imageIsAvatar: Bool {
        guard variant == .social, let aspect = imageAspect else { return false }
        return aspect > 0.85 && aspect < 1.18
    }
}

/// A run of text placed on a web card.
struct WebTextBlock {
    var text: NSAttributedString
    var frame: CGRect
    var maxLines: Int
}

/// Where everything goes on a web card of a given width, for each layout variant
/// (DESIGN.md §7.1, §7.2). Pure geometry plus text measurement, so it's tested directly.
struct WebCardLayout {
    static let defaultWidth: CGFloat = 360
    static let widthRange: ClosedRange<CGFloat> = 240...640
    static let minimumSize = CGSize(width: widthRange.lowerBound, height: 120)
    static let padding: CGFloat = 16
    static let heroInset: CGFloat = 8
    static let heroCornerRadius: CGFloat = 9

    var size: CGSize
    /// The page image: across the top (hero, article, media), down the left (portrait) or
    /// below the post (social).
    var image: CGRect?
    /// The palette wash over the bottom of the image.
    var wash: CGRect?
    /// Favicon squircle, or the round avatar on social posts.
    var icon: CGRect?
    var iconIsRound = false
    var playButton: CGRect?
    var durationBadge: CGRect?
    /// The whole card is a mesh gradient (compact and fallback), rather than a hint of one.
    var fullMesh = false
    var blocks: [WebTextBlock] = []
    /// Placeholder bars while loading.
    var skeletonBars: [CGRect] = []

    init(content: WebCardContent, width requestedWidth: CGFloat, appearance: CanvasAppearance) {
        let width = min(max(requestedWidth, Self.widthRange.lowerBound), Self.widthRange.upperBound)
        size = CGSize(width: width, height: 0)
        let style = WebCardTypography(
            appearance: appearance, palette: content.palette, fullMesh: [.compact, .fallback].contains(content.variant)
        )
        if content.isLoading {
            layoutSkeleton(width: width)
            return
        }
        switch content.variant {
        case .hero, .article, .media:
            layoutHero(content, width: width, style: style)
        case .portrait:
            layoutPortrait(content, width: width, style: style)
        case .social:
            layoutSocial(content, width: width, style: style)
        case .compact, .fallback:
            layoutCompact(content, width: width, style: style)
        }
        size.height = max(size.height, Self.minimumSize.height)
    }

    /// Text blocks in drawing order.
    var textFrames: [CGRect] { blocks.map(\.frame) }

    // MARK: Variants

    private mutating func layoutHero(_ content: WebCardContent, width: CGFloat, style: WebCardTypography) {
        let p = Self.padding
        let heroWidth = width - Self.heroInset * 2
        let hero = CGRect(x: Self.heroInset, y: Self.heroInset, width: heroWidth, height: (heroWidth * 9 / 16).rounded())
        image = hero
        wash = CGRect(x: hero.minX, y: hero.minY + hero.height * 0.55, width: hero.width, height: hero.height * 0.45)
        if content.variant == .media {
            let side: CGFloat = min(56, hero.height * 0.36)
            playButton = CGRect(x: hero.midX - side / 2, y: hero.midY - side / 2, width: side, height: side)
            if let duration = content.duration, duration > 0 {
                let label = style.badge(Self.formatDuration(duration))
                let textSize = label.size()
                let badge = CGSize(width: ceil(textSize.width) + 14, height: 20)
                durationBadge = CGRect(x: hero.maxX - 10 - badge.width, y: hero.maxY - 10 - badge.height, width: badge.width, height: badge.height)
                blocks.append(WebTextBlock(
                    text: label,
                    frame: CGRect(x: durationBadge!.minX + 7, y: durationBadge!.midY - ceil(textSize.height) / 2, width: ceil(textSize.width) + 1, height: ceil(textSize.height)),
                    maxLines: 1
                ))
            }
        }
        var y = hero.maxY + 14
        y = siteRow(content, y: y, x: p, width: width - 2 * p, iconSide: 18, style: style)
        y += 9
        let title = Self.block(style.title(content.title, size: width >= 420 ? 19 : 17), x: p, y: y, width: width - 2 * p, maxLines: content.pageDescription == nil ? 3 : 2)
        blocks.append(title)
        y = title.frame.maxY + 6
        if let description = content.pageDescription {
            let block = Self.block(style.body(description, size: 13), x: p, y: y, width: width - 2 * p, maxLines: 3)
            blocks.append(block)
            y = block.frame.maxY + 6
        }
        y = footer(content, y: y + 4, width: width, byline: content.variant == .article ? Self.byline(content) : nil, style: style)
        size.height = (y + 14).rounded(.up)
    }

    private mutating func layoutPortrait(_ content: WebCardContent, width: CGFloat, style: WebCardTypography) {
        let p = Self.padding
        let imageWidth = (min(132, width * 0.34)).rounded()
        let aspect = content.imageAspect ?? 0.75
        let imageHeight = min(max(imageWidth / aspect, imageWidth * 0.8), imageWidth * 1.6).rounded()
        let frame = CGRect(x: Self.heroInset, y: Self.heroInset, width: imageWidth, height: imageHeight)
        image = frame
        let x = frame.maxX + 14
        let columnWidth = width - x - p
        var y: CGFloat = 22
        y = siteRow(content, y: y, x: x, width: columnWidth, iconSide: 16, style: style)
        y += 8
        let title = Self.block(style.title(content.title, size: 15), x: x, y: y, width: columnWidth, maxLines: 3)
        blocks.append(title)
        y = title.frame.maxY + 5
        if let description = content.pageDescription {
            let block = Self.block(style.body(description, size: 12.5), x: x, y: y, width: columnWidth, maxLines: 3)
            blocks.append(block)
            y = block.frame.maxY + 5
        }
        // The open hint sits at the bottom of the text column, or under the image if that's lower.
        let bottom = max(y + 6, frame.maxY - 16, Self.minimumSize.height - 12 - 15)
        y = footer(content, y: bottom, width: width, byline: nil, style: style, left: x)
        size.height = max(y + 12, frame.maxY + Self.heroInset).rounded(.up)
        // The image runs the full height of the card, like a cover on a shelf.
        image = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: size.height - 2 * Self.heroInset)
    }

    private mutating func layoutSocial(_ content: WebCardContent, width: CGFloat, style: WebCardTypography) {
        let p = Self.padding
        let avatar = CGRect(x: p, y: 22, width: 36, height: 36)
        icon = avatar
        iconIsRound = true
        let names = Self.socialNames(content)
        let x = avatar.maxX + 10
        let name = Self.block(style.title(names.name, size: 14), x: x, y: avatar.minY + 1, width: width - x - p, maxLines: 1)
        let handle = Self.block(style.secondary(names.handle, size: 12), x: x, y: name.frame.maxY + 1, width: width - x - p, maxLines: 1)
        blocks += [name, handle]
        var y = max(avatar.maxY, handle.frame.maxY) + 12
        let quoteText = content.pageDescription ?? content.title
        let quote = Self.block(style.quote(quoteText, size: 15), x: p, y: y, width: width - 2 * p, maxLines: 6)
        blocks.append(quote)
        y = quote.frame.maxY + 12
        if let aspect = content.imageAspect, !content.imageIsAvatar {
            let mediaWidth = width - Self.heroInset * 2
            let media = CGRect(x: Self.heroInset, y: y, width: mediaWidth, height: (mediaWidth / min(max(aspect, 1), 2)).rounded())
            image = media
            y = media.maxY + 10
        }
        y = footer(content, y: y, width: width, byline: content.domain, style: style)
        size.height = (y + 14).rounded(.up)
    }

    private mutating func layoutCompact(_ content: WebCardContent, width: CGFloat, style: WebCardTypography) {
        let p = Self.padding
        fullMesh = true
        let badge = CGRect(x: p, y: 22, width: 44, height: 44)
        icon = badge
        let x = badge.maxX + 12
        let site = Self.block(style.title(content.siteName ?? content.domain, size: 13), x: x, y: badge.minY + 4, width: width - x - p, maxLines: 1)
        let domain = Self.block(style.secondary(content.domain, size: 12), x: x, y: site.frame.maxY + 1, width: width - x - p, maxLines: 1)
        blocks += [site, domain]
        var y = badge.maxY + 14
        let title = Self.block(style.display(content.title, size: 20), x: p, y: y, width: width - 2 * p, maxLines: 3)
        blocks.append(title)
        y = title.frame.maxY + 6
        if let description = content.pageDescription {
            let block = Self.block(style.body(description, size: 13), x: p, y: y, width: width - 2 * p, maxLines: 2)
            blocks.append(block)
            y = block.frame.maxY + 6
        }
        if content.variant == .fallback {
            let note = Self.block(style.tertiary("Preview unavailable · ⌘R to retry", size: 11), x: p, y: y + 2, width: width - 2 * p, maxLines: 1)
            blocks.append(note)
            y = note.frame.maxY + 6
        }
        y = footer(content, y: y + 4, width: width, byline: nil, style: style)
        size.height = (y + 14).rounded(.up)
    }

    private mutating func layoutSkeleton(width: CGFloat) {
        let heroWidth = width - Self.heroInset * 2
        let hero = CGRect(x: Self.heroInset, y: Self.heroInset, width: heroWidth, height: (heroWidth * 9 / 16).rounded())
        skeletonBars = [hero]
        var y = hero.maxY + 16
        skeletonBars.append(CGRect(x: Self.padding, y: y, width: width * 0.38, height: 8))
        y += 22
        for fraction in [0.92, 0.74] {
            skeletonBars.append(CGRect(x: Self.padding, y: y, width: (width - 2 * Self.padding) * fraction, height: 12))
            y += 20
        }
        y += 4
        for fraction in [0.96, 0.88, 0.6] {
            skeletonBars.append(CGRect(x: Self.padding, y: y, width: (width - 2 * Self.padding) * fraction, height: 8))
            y += 15
        }
        size.height = (y + 14).rounded(.up)
    }

    // MARK: Rows

    /// Favicon, then "SITE · domain". Returns the row's bottom.
    private mutating func siteRow(_ content: WebCardContent, y: CGFloat, x: CGFloat, width: CGFloat, iconSide: CGFloat, style: WebCardTypography) -> CGFloat {
        let iconFrame = CGRect(x: x, y: y, width: iconSide, height: iconSide)
        icon = iconFrame
        let textX = iconFrame.maxX + 7
        let label = style.siteLine(site: content.siteName, domain: content.domain)
        let height = ceil(label.size().height)
        blocks.append(WebTextBlock(
            text: label,
            frame: CGRect(x: textX, y: iconFrame.midY - height / 2, width: max(x + width - textX, 1), height: height),
            maxLines: 1
        ))
        return iconFrame.maxY
    }

    /// The bottom row: a byline or domain on the left, "↗ Open" on the right. Returns its bottom.
    private mutating func footer(
        _ content: WebCardContent, y: CGFloat, width: CGFloat, byline: String?, style: WebCardTypography, left: CGFloat? = nil
    ) -> CGFloat {
        let p = Self.padding
        let open = style.openHint()
        let openSize = open.size()
        let height = ceil(max(openSize.height, 15))
        let openFrame = CGRect(x: width - p - ceil(openSize.width) - 1, y: y, width: ceil(openSize.width) + 1, height: height)
        blocks.append(WebTextBlock(text: open, frame: openFrame, maxLines: 1))
        if let byline, !byline.isEmpty {
            let x = left ?? p
            blocks.append(WebTextBlock(
                text: style.tertiary(byline, size: 11.5),
                frame: CGRect(x: x, y: y, width: max(openFrame.minX - 10 - x, 1), height: height),
                maxLines: 1
            ))
        }
        return openFrame.maxY
    }

    // MARK: Text helpers

    /// Measures `text` at `width`, keeping at most `maxLines` lines (the rest is cut off with
    /// an ellipsis when drawn).
    static func block(_ text: NSAttributedString, x: CGFloat, y: CGFloat, width: CGFloat, maxLines: Int) -> WebTextBlock {
        let measured = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        let font = (text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil) ?? .systemFont(ofSize: 13)
        let paragraph = text.length > 0 ? text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
        let lineHeight = ceil(font.ascender - font.descender + font.leading) * max(paragraph?.lineHeightMultiple ?? 1, 1)
        let height = min(ceil(measured), ceil(lineHeight * CGFloat(maxLines)) + 1)
        return WebTextBlock(text: text, frame: CGRect(x: x, y: y, width: width, height: max(height, ceil(lineHeight))), maxLines: maxLines)
    }

    /// "4:13" or "1:02:03".
    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// "J. Rivera · Oct 12, 2026".
    static func byline(_ content: WebCardContent) -> String? {
        let date = content.publishedAt.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) }
        let parts = [content.author, date].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The poster's name and handle, from titles like "Someone on X" or "Someone (@handle)".
    static func socialNames(_ content: WebCardContent) -> (name: String, handle: String) {
        var name = content.title
        for marker in [" on X", " on Twitter", " on Threads", " on Instagram", " on LinkedIn", " on Bluesky"] {
            if let range = name.range(of: marker) { name = String(name[..<range.lowerBound]) }
        }
        var handle = content.author ?? content.siteName ?? content.domain
        if let open = name.range(of: " ("), name.hasSuffix(")") {
            handle = String(name[open.upperBound..<name.index(before: name.endIndex)])
            name = String(name[..<open.lowerBound])
        }
        if name.count > 60 { name = String(name.prefix(60)) }
        return (name, handle)
    }
}
