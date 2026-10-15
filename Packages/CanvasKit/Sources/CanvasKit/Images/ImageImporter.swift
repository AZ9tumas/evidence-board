import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import BoardKit

/// An image ready to go into a board's asset table.
public struct ImportedImage: Sendable {
    public let id: AssetID
    public let asset: Asset
    public let pixelSize: CGSize
}

public enum ImageImportError: Error, Equatable {
    case unreadable
    case tooLarge
    case encodingFailed
}

/// Turns dropped, pasted or picked images into board assets (DESIGN.md §4.3, §8.8).
///
/// PNG and upright JPEG files that already fit are stored byte for byte. Everything else
/// (HEIC, TIFF, WebP, GIF, rotated JPEGs, PDFs, anything over the size cap) is decoded with
/// its orientation applied, shrunk to fit, and re-encoded: JPEG if opaque, PNG if it has
/// transparency. Assets are named by the SHA-256 of their bytes, so the same image is only
/// stored once. Safe to call from any thread.
public enum ImageImporter {
    /// Long-side cap for stored images, in pixels.
    public static let maxPixelSize = 4096
    static let jpegQuality = 0.88
    /// Refuse anything that would decode to more than this many pixels.
    static let maxSourcePixels = 100_000_000
    static let maxFileBytes = 200 * 1024 * 1024

    public static func importFile(at url: URL, maxPixelSize: Int = maxPixelSize) throws -> ImportedImage {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > maxFileBytes { throw ImageImportError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try importData(data, maxPixelSize: maxPixelSize)
    }

    public static func importData(_ data: Data, maxPixelSize: Int = maxPixelSize) throws -> ImportedImage {
        guard data.count <= maxFileBytes else { throw ImageImportError.tooLarge }
        if data.starts(with: Array("%PDF".utf8)) {
            return try importPDF(data, maxPixelSize: maxPixelSize)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ImageImportError.unreadable }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { throw ImageImportError.unreadable }
        guard width * height <= maxSourcePixels else { throw ImageImportError.tooLarge }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false

        let isPortable = type == UTType.png.identifier || type == UTType.jpeg.identifier
        if isPortable, orientation == 1, max(width, height) <= maxPixelSize {
            let mime = type == UTType.png.identifier ? "image/png" : "image/jpeg"
            return finish(data, mime: mime, width: width, height: height)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageImportError.unreadable
        }
        return try encode(image, opaque: !hasAlpha)
    }

    /// Renders the first page of a PDF on white, at up to 2× its natural size.
    static func importPDF(_ data: Data, maxPixelSize: Int) throws -> ImportedImage {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1)
        else { throw ImageImportError.unreadable }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { throw ImageImportError.unreadable }
        let scale = min(2, CGFloat(maxPixelSize) / max(box.width, box.height))
        let width = Int((box.width * scale).rounded())
        let height = Int((box.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { throw ImageImportError.encodingFailed }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw ImageImportError.encodingFailed }
        // Documents are mostly text and line art, which JPEG smears.
        return try encode(image, as: .png)
    }

    static func encode(_ image: CGImage, opaque: Bool) throws -> ImportedImage {
        try encode(image, as: opaque ? .jpeg : .png)
    }

    private static func encode(_ image: CGImage, as type: UTType) throws -> ImportedImage {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw ImageImportError.encodingFailed
        }
        let properties: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageImportError.encodingFailed }
        return finish(output as Data, mime: type == .jpeg ? "image/jpeg" : "image/png", width: image.width, height: image.height)
    }

    private static func finish(_ data: Data, mime: String, width: Int, height: Int) -> ImportedImage {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ImportedImage(
            id: "sha256-" + digest,
            asset: Asset(mime: mime, pixelWidth: width, pixelHeight: height, data: data),
            pixelSize: CGSize(width: width, height: height)
        )
    }
}
