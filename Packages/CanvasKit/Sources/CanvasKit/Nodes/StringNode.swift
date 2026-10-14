import Foundation
import QuartzCore
import BoardKit

/// One string between two pins.
///
/// M0 draws a solid stroke with a soft shadow. The gradient along the thread, the fiber
/// texture, labels and arrows come with M3.
@MainActor
final class StringNode {
    let id: UUID
    let layer = CAShapeLayer()

    init(string: BoardString, from a: CGPoint, to b: CGPoint, fan: CGFloat, appearance: CanvasAppearance, scale: CGFloat) {
        id = string.id
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.shadowColor = RGBA.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.contentsScale = scale
        update(string: string, from: a, to: b, fan: fan, appearance: appearance)
    }

    func update(string: BoardString, from a: CGPoint, to b: CGPoint, fan: CGFloat, appearance: CanvasAppearance) {
        let width = CGFloat(string.thickness)
        let path = CanvasGeometry.stringPath(from: a, to: b, sag: CGFloat(string.sag), fan: fan)
        layer.path = path
        layer.lineWidth = width
        layer.strokeColor = appearance.gradient(for: string.color).from.cgColor
        let dashes: [CGFloat]? = switch string.stroke {
        case .solid: nil
        case .dashed: [width * 3, width * 2.5]
        case .dotted: [0, width * 2.2] // zero-length dashes with round caps draw dots
        }
        layer.lineDashPattern = dashes?.map { NSNumber(value: Double($0)) }
        layer.shadowPath = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }
}
