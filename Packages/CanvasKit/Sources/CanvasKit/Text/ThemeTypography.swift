import AppKit
import BoardKit

enum ThemeTypography {
    static func font(_ family: ThemeFont, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        if family == .system { return system }
        if family == .monospaced { return .monospacedSystemFont(ofSize: size, weight: weight) }
        if family == .rounded {
            return system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        }
        let name: String = switch family {
        case .archival: "Baskerville"
        case .chalk: "Chalkboard"
        case .handwriting: "Noteworthy-Light"
        case .technical: "AvenirNextCondensed-Regular"
        case .casual: "MarkerFelt-Thin"
        case .editorial: "Georgia"
        default: ""
        }
        let base = NSFont(name: name, size: size) ?? system
        if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            let bold = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.bold)), size: size)
            // Some handwriting faces have no bold member. Explicit formatting still wins.
            return bold?.fontDescriptor.symbolicTraits.contains(.bold) == true ? bold! : system
        }
        return base
    }
}
