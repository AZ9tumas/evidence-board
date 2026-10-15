import Foundation
import BoardKit

/// Pixel dimensions of a fetched image.
public struct PixelSize: Sendable, Equatable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var aspect: Double { Double(width) / Double(max(height, 1)) }
}

/// Chooses a web card's layout from what the page turned out to have (DESIGN.md §7.2).
public enum VariantRules {
    /// Images smaller than this on either side aren't worth a hero.
    public static let minimumImageSide = 200

    public static func variant(for kind: PageInfo.Kind, image: PixelSize?) -> LinkVariant {
        let usable = image.flatMap { $0.width >= minimumImageSide && $0.height >= minimumImageSide ? $0 : nil }
        switch kind {
        case .social:
            return .social
        case .video where usable != nil:
            return .media
        default:
            break
        }
        guard let usable else { return .compact }
        if usable.aspect < 1.2 { return .portrait }
        if usable.width >= 600, usable.aspect <= 2.4 {
            return kind == .article ? .article : .hero
        }
        // Too small or too wide for a hero: a portrait-style thumbnail still reads well.
        return usable.aspect <= 2.4 ? .portrait : .compact
    }
}
