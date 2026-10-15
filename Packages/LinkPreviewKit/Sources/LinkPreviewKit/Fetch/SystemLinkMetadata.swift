#if canImport(LinkPresentation)
import Foundation
import LinkPresentation
import UniformTypeIdentifiers

/// What the system's LinkPresentation fetcher found, as plain values.
public struct SystemLinkResult: Sendable {
    public var metadata: SystemMetadata
    public var image: Data?
    public var icon: Data?
}

/// Asks `LPMetadataProvider` about a page, in parallel with our own head fetch. It fills in
/// titles and images for pages that only describe themselves to a browser (DESIGN.md §7.3).
public enum SystemLinkMetadata {
    public static func fetch(_ url: URL, timeout: TimeInterval = 10) async -> SystemLinkResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<SystemLinkResult?, Never>) in
            let provider = LPMetadataProvider()
            provider.timeout = timeout
            provider.shouldFetchSubresources = true
            // LinkPresentation calls back on its own queues; the provider must stay alive until then.
            let keepAlive = UncheckedBox(provider)
            provider.startFetchingMetadata(for: url) { @Sendable metadata, error in
                guard let metadata, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let title = metadata.title
                let hasVideo = metadata.videoProvider != nil || metadata.remoteVideoURL != nil
                let iconProvider = UncheckedBox(metadata.iconProvider)
                loadImage(UncheckedBox(metadata.imageProvider)) { image in
                    loadImage(iconProvider) { icon in
                        _ = keepAlive
                        continuation.resume(returning: SystemLinkResult(
                            metadata: SystemMetadata(title: title, hasVideo: hasVideo), image: image, icon: icon
                        ))
                    }
                }
            }
        }
    }

    private static func loadImage(_ box: UncheckedBox<NSItemProvider?>, completion: @escaping @Sendable (Data?) -> Void) {
        guard let provider = box.value, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            completion(nil)
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { @Sendable data, _ in
            completion(data)
        }
    }
}

/// Carries a value LinkPresentation hands out across its callbacks.
final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
#endif
