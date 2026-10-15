import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import BoardKit
@testable import CanvasKit

// MARK: - Helpers

/// A solid-color test image, with an alpha channel when `opaque` is false.
func makeImage(width: Int, height: Int, opaque: Bool = true) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipFirst : CGImageAlphaInfo.premultipliedFirst
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: opaque ? 1 : 0.5))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// `image` encoded as `type`, optionally tagged with an EXIF orientation.
func encoded(_ image: CGImage, as type: UTType, orientation: Int? = nil) -> Data? {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
}

// MARK: - Layout

@Suite("Image card layout")
struct ImageCardLayoutTests {
    @Test func polaroidSizeFitsThePhotoAspect() {
        let size = ImageCardLayout.cardSize(for: CGSize(width: 4000, height: 3000), style: .polaroid)
        let photo = ImageCardLayout.photoRect(for: .polaroid, in: size)
        #expect(abs(photo.width / photo.height - 4.0 / 3.0) < 0.01)
        #expect(photo.width == 300)
        #expect(size.height - photo.maxY == ImageCardLayout.polaroidBottom)
    }

    @Test func borderlessIsAllPhoto() {
        let size = ImageCardLayout.cardSize(for: CGSize(width: 1000, height: 2000), style: .borderless)
        #expect(ImageCardLayout.photoRect(for: .borderless, in: size) == CGRect(origin: .zero, size: size))
        #expect(size == CGSize(width: 150, height: 300))
    }

    @Test func visibleCropFillsAWiderFrame() {
        // A square image in a 2:1 frame shows a centered band half as tall.
        let crop = ImageCardLayout.visibleCrop(crop: nil, imageAspect: 1, photoSize: CGSize(width: 200, height: 100))
        #expect(crop == CGRect(x: 0, y: 0.25, width: 1, height: 0.5))
    }

    @Test func visibleCropFillsATallerFrame() {
        let crop = ImageCardLayout.visibleCrop(crop: nil, imageAspect: 2, photoSize: CGSize(width: 100, height: 100))
        #expect(crop == CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
    }

    @Test func storedCropIsTrimmedAroundItsCenter() {
        let stored = Rect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        let crop = ImageCardLayout.visibleCrop(crop: stored, imageAspect: 1, photoSize: CGSize(width: 100, height: 50))
        #expect(crop == CGRect(x: 0.5, y: 0.625, width: 0.5, height: 0.25))
    }

    @Test func neededPixelsGrowWithZoomAndCrop() {
        let photo = CGSize(width: 300, height: 225)
        let whole = ImageCardLayout.neededLongSide(crop: nil, imageAspect: 4.0 / 3.0, photoSize: photo, scale: 2)
        #expect(whole == 600)
        let quarter = ImageCardLayout.neededLongSide(
            crop: Rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), imageAspect: 4.0 / 3.0, photoSize: photo, scale: 2
        )
        #expect(quarter == 1200)
    }

    @Test func bucketsArePowersOfTwo() {
        #expect(ImageCardLayout.bucket(1) == 64)
        #expect(ImageCardLayout.bucket(600) == 1024)
        #expect(ImageCardLayout.bucket(1024) == 1024)
        #expect(ImageCardLayout.bucket(50_000) == 8192)
    }

    @Test func zoomingStaysInsideTheImageAndKeepsShape() {
        let start = CGRect(x: 0, y: 0.25, width: 1, height: 0.5)
        let zoomedIn = ImageCardLayout.zoomCrop(start, by: 2, around: CGPoint(x: 0.9, y: 0.5))
        #expect(abs(zoomedIn.width - 0.5) < 1e-9 && abs(zoomedIn.height - 0.25) < 1e-9)
        #expect(zoomedIn.maxX <= 1 && zoomedIn.minX >= 0)

        let zoomedOut = ImageCardLayout.zoomCrop(zoomedIn, by: 0.01, around: CGPoint(x: 0.5, y: 0.5))
        #expect(abs(zoomedOut.width - 1) < 1e-9 && abs(zoomedOut.height - 0.5) < 1e-9)
        #expect(zoomedOut.minY >= 0 && zoomedOut.maxY <= 1)
    }

    @Test func pixelRectStaysInsideTheImage() {
        let rect = ImageCardLayout.pixelRect(for: CGRect(x: 0.9, y: 0.9, width: 0.2, height: 0.2), imageSize: CGSize(width: 100, height: 50))
        #expect(rect == CGRect(x: 90, y: 45, width: 10, height: 5))
    }
}

// MARK: - Import

@Suite("Image import")
struct ImageImporterTests {
    @Test func smallPNGIsStoredAsIs() throws {
        let data = try #require(encoded(makeImage(width: 64, height: 32, opaque: false), as: .png))
        let imported = try ImageImporter.importData(data)
        #expect(imported.asset.decodedData() == data)
        #expect(imported.asset.mime == "image/png")
        #expect(imported.pixelSize == CGSize(width: 64, height: 32))
        #expect(imported.id.hasPrefix("sha256-") && imported.id.count == 7 + 64)
    }

    @Test func sameBytesGiveTheSameAsset() throws {
        let data = try #require(encoded(makeImage(width: 20, height: 20), as: .jpeg))
        #expect(try ImageImporter.importData(data).id == ImageImporter.importData(data).id)
    }

    @Test func oversizedImagesAreShrunk() throws {
        let data = try #require(encoded(makeImage(width: 5000, height: 1000), as: .png))
        let imported = try ImageImporter.importData(data)
        #expect(imported.pixelSize == CGSize(width: 4096, height: 819) || imported.pixelSize == CGSize(width: 4096, height: 820))
        #expect(imported.asset.mime == "image/jpeg") // opaque, so re-encoded as JPEG
    }

    @Test func rotatedJPEGsAreTurnedUpright() throws {
        // Orientation 6 means "rotate 90° clockwise to display": a 300×100 sensor image shows as 100×300.
        let data = try #require(encoded(makeImage(width: 300, height: 100), as: .jpeg, orientation: 6))
        let imported = try ImageImporter.importData(data)
        #expect(imported.pixelSize == CGSize(width: 100, height: 300))
    }

    @Test func tiffBecomesPNGWhenTransparent() throws {
        let data = try #require(encoded(makeImage(width: 40, height: 40, opaque: false), as: .tiff))
        let imported = try ImageImporter.importData(data)
        #expect(imported.asset.mime == "image/png")
    }

    @Test func heicBecomesJPEG() throws {
        // Some virtual machines can't encode HEIC; there's nothing to test then.
        guard let data = encoded(makeImage(width: 64, height: 48), as: .heic) else { return }
        let imported = try ImageImporter.importData(data)
        #expect(imported.asset.mime == "image/jpeg")
        #expect(imported.pixelSize == CGSize(width: 64, height: 48))
    }

    @Test func pdfFirstPageIsRendered() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 50, height: 50))
        context.endPDFPage()
        context.closePDF()

        let imported = try ImageImporter.importData(data as Data)
        #expect(imported.asset.mime == "image/png")
        #expect(imported.pixelSize == CGSize(width: 400, height: 200))
    }

    @Test func junkIsRejected() {
        #expect(throws: ImageImportError.unreadable) {
            try ImageImporter.importData(Data("definitely not an image".utf8))
        }
    }
}

// MARK: - Decoding

@MainActor
@Suite("Image store")
struct ImageStoreTests {
    @Test func decodesStraightToTheRequestedSize() throws {
        let data = try #require(encoded(makeImage(width: 2000, height: 1000), as: .jpeg))
        let decoded = try #require(ImageStore.decode(base64: data.base64EncodedString(), maxLongSide: 256))
        #expect(decoded.image.width == 256 && decoded.image.height == 128)
    }

    @Test func loadsOnceAndReusesLargerDecodes() async throws {
        let data = try #require(encoded(makeImage(width: 1600, height: 800), as: .jpeg))
        let store = ImageStore(budget: 64 << 20)
        let image = await withCheckedContinuation { continuation in
            store.load(asset: "a", base64: data.base64EncodedString(), longSide: 900) { continuation.resume(returning: $0) }
        }
        #expect(image.width == 1024) // bucketed up
        #expect(store.cachedImage(asset: "a", longSide: 300) === image)
        #expect(store.cachedImage(asset: "a", longSide: 2000) == nil)
    }

    @Test func evictsLeastRecentlyUsedPastTheBudget() async throws {
        let data = try #require(encoded(makeImage(width: 512, height: 512), as: .jpeg))
        // Room for about one 512×512 decode (1 MB).
        let store = ImageStore(budget: 1_200_000)
        for asset in ["a", "b"] {
            _ = await withCheckedContinuation { continuation in
                store.load(asset: asset, base64: data.base64EncodedString(), longSide: 512) { continuation.resume(returning: $0) }
            }
        }
        #expect(store.cachedImage(asset: "a", longSide: 512) == nil)
        #expect(store.cachedImage(asset: "b", longSide: 512) != nil)
        #expect(store.totalCost <= store.budget)
    }
}
