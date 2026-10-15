import CoreGraphics
import Foundation
import BoardKit

/// Where the photo and caption sit inside an image card, and which part of the photo shows.
///
/// All rects are in card-local points, top-left origin. Crops are normalized to the image
/// (0…1, top-left origin) and never touch the stored bytes.
enum ImageCardLayout {
    /// Height of the polaroid's thick bottom strip, where the caption goes.
    static let polaroidBottom: CGFloat = 52
    static let minimumSize = CGSize(width: 80, height: 80)

    static func cardCornerRadius(for style: ImageFrameStyle) -> CGFloat {
        switch style {
        case .polaroid: 4
        case .photo: 6
        case .borderless: 12
        }
    }

    static func photoCornerRadius(for style: ImageFrameStyle) -> CGFloat {
        switch style {
        case .polaroid: 2
        case .photo: 3
        case .borderless: 12
        }
    }

    /// The photo's frame inside a card of `size`.
    static func photoRect(for style: ImageFrameStyle, in size: CGSize) -> CGRect {
        switch style {
        case .polaroid:
            CGRect(x: 12, y: 12, width: max(size.width - 24, 1), height: max(size.height - 12 - polaroidBottom, 1))
        case .photo:
            CGRect(x: 8, y: 8, width: max(size.width - 16, 1), height: max(size.height - 16, 1))
        case .borderless:
            CGRect(origin: .zero, size: size)
        }
    }

    /// Polaroids write the caption on the paper strip; the other styles lay it over the photo.
    static func captionIsOverlaid(for style: ImageFrameStyle) -> Bool {
        style != .polaroid
    }

    static func captionRect(for style: ImageFrameStyle, in size: CGSize) -> CGRect {
        switch style {
        case .polaroid:
            return CGRect(x: 14, y: size.height - polaroidBottom + 10, width: max(size.width - 28, 1), height: polaroidBottom - 20)
        case .photo, .borderless:
            let photo = photoRect(for: style, in: size)
            return CGRect(x: photo.minX + 12, y: photo.maxY - 34, width: max(photo.width - 24, 1), height: 24)
        }
    }

    /// A card whose photo area fits `pixelSize`'s aspect ratio within `longSide` points.
    static func cardSize(for pixelSize: CGSize, style: ImageFrameStyle, longSide: CGFloat = 300) -> CGSize {
        let aspect = pixelSize.width / max(pixelSize.height, 1)
        var photo = aspect >= 1
            ? CGSize(width: longSide, height: longSide / aspect)
            : CGSize(width: longSide * aspect, height: longSide)
        photo.width = max(photo.width, 60)
        photo.height = max(photo.height, 60)
        switch style {
        case .polaroid: return CGSize(width: photo.width + 24, height: photo.height + 12 + polaroidBottom)
        case .photo: return CGSize(width: photo.width + 16, height: photo.height + 16)
        case .borderless: return photo
        }
    }

    /// The normalized part of the image that shows: `crop` (or the whole image), trimmed
    /// around its center to the photo area's aspect ratio. This is "aspect fill" of the crop.
    static func visibleCrop(crop: Rect?, imageAspect: CGFloat, photoSize: CGSize) -> CGRect {
        var region = crop.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        region = clampCrop(region)
        let target = photoSize.width / max(photoSize.height, 0.0001)
        // The crop's aspect ratio in pixels: normalized width × image aspect over normalized height.
        let current = region.width * imageAspect / max(region.height, 0.0001)
        if current > target {
            let width = region.height * target / imageAspect
            region.origin.x += (region.width - width) / 2
            region.size.width = width
        } else {
            let height = region.width * imageAspect / target
            region.origin.y += (region.height - height) / 2
            region.size.height = height
        }
        return region
    }

    /// `crop` (normalized) in pixels of an image of `imageSize`, kept inside the image.
    static func pixelRect(for crop: CGRect, imageSize: CGSize) -> CGRect {
        let rect = CGRect(
            x: (crop.minX * imageSize.width).rounded(),
            y: (crop.minY * imageSize.height).rounded(),
            width: max((crop.width * imageSize.width).rounded(), 1),
            height: max((crop.height * imageSize.height).rounded(), 1)
        )
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// How many pixels the decoded image needs on its long side so that the visible part fills
    /// the photo area at `scale` pixels per point.
    static func neededLongSide(crop: Rect?, imageAspect: CGFloat, photoSize: CGSize, scale: CGFloat) -> Int {
        let visible = visibleCrop(crop: crop, imageAspect: imageAspect, photoSize: photoSize)
        // Image size with a long side of 1.
        let unit = imageAspect >= 1
            ? CGSize(width: 1, height: 1 / imageAspect)
            : CGSize(width: imageAspect, height: 1)
        let needed = max(
            photoSize.width * scale / max(visible.width * unit.width, 0.0001),
            photoSize.height * scale / max(visible.height * unit.height, 0.0001)
        )
        return Int(min(needed, 100_000).rounded(.up))
    }

    /// Rounds a pixel size up to a power of two between 64 and 8192, so each image is only
    /// ever decoded at a handful of sizes.
    static func bucket(_ pixels: Int) -> Int {
        var size = 64
        while size < pixels && size < 8192 { size *= 2 }
        return size
    }

    /// Keeps a normalized crop inside the image.
    static func clampCrop(_ rect: CGRect) -> CGRect {
        let width = min(max(rect.width, 0.01), 1)
        let height = min(max(rect.height, 0.01), 1)
        return CGRect(
            x: min(max(rect.minX, 0), 1 - width),
            y: min(max(rect.minY, 0), 1 - height),
            width: width,
            height: height
        )
    }

    /// Zooms a crop by `factor` (more than 1 zooms in) around `anchor` (normalized, inside the
    /// crop), keeping its aspect ratio and keeping it inside the image.
    static func zoomCrop(_ crop: CGRect, by factor: CGFloat, around anchor: CGPoint) -> CGRect {
        let largest = min(1 / crop.width, 1 / crop.height)
        let scale = min(max(1 / factor, 0.05 / min(crop.width, crop.height)), largest)
        let width = crop.width * scale
        let height = crop.height * scale
        let rect = CGRect(
            x: anchor.x - (anchor.x - crop.minX) * scale,
            y: anchor.y - (anchor.y - crop.minY) * scale,
            width: width,
            height: height
        )
        return clampCrop(rect)
    }
}
