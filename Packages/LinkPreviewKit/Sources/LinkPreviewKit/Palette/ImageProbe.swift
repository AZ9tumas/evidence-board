#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import BoardKit

/// Reads just enough of an encoded image to size it and take its palette, with ImageIO and a
/// 100 MP limit against decompression bombs (DESIGN.md §13).
public enum ImageProbe {
    public static let maxPixels = 100_000_000

    /// Display size (after EXIF rotation), or `nil` if it isn't a readable, sane image.
    public static func pixelSize(of data: Data) -> PixelSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width * height <= maxPixels else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    }

    /// The five swatches, from a 64 px thumbnail.
    public static func palette(of data: Data) -> LinkPalette? {
        guard pixelSize(of: data) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
              ] as CFDictionary) else { return nil }
        return palette(of: thumbnail)
    }

    public static func palette(of image: CGImage) -> LinkPalette? {
        let side = 64
        let width = min(image.width, side)
        let height = min(image.height, side)
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pointer = context.data else { return nil }
        let buffer = UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: width * height * 4)
        return PaletteExtractor.palette(rgba: Array(buffer))
    }
}
#endif
