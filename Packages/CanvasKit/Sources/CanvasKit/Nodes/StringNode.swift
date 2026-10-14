import Foundation
import QuartzCore
import BoardKit

/// One string between two pins.
///
/// M1 draws a solid stroke with a soft shadow and a knot over each pin. The gradient along
/// the thread, the fiber texture, labels and arrows come with M3.
@MainActor
final class StringNode {
    let layer = CALayer()
    private(set) var string: BoardString
    private let thread = CAShapeLayer()
    private let knots = CAShapeLayer()

    init(string: BoardString, scale: CGFloat) {
        self.string = string
        thread.fillColor = nil
        thread.lineCap = .round
        thread.lineJoin = .round
        thread.shadowColor = RGBA.black.cgColor
        thread.shadowOpacity = 0.35
        thread.shadowRadius = 2
        thread.shadowOffset = CGSize(width: 0, height: 3)
        layer.addSublayer(thread)
        layer.addSublayer(knots)
        setContentsScale(scale)
    }

    func setContentsScale(_ scale: CGFloat) {
        for item: CALayer in [layer, thread, knots] { item.contentsScale = scale }
    }

    func update(string: BoardString, from a: CGPoint, to b: CGPoint, fan: CGFloat, appearance: CanvasAppearance) {
        self.string = string
        let width = CGFloat(string.thickness)
        let color = appearance.gradient(for: string.color).from.cgColor
        let path = CanvasGeometry.stringPath(from: a, to: b, sag: CGFloat(string.sag), fan: fan)
        thread.path = path
        thread.lineWidth = width
        thread.strokeColor = color
        let dashes: [CGFloat]? = switch string.stroke {
        case .solid: nil
        case .dashed: [width * 3, width * 2.5]
        case .dotted: [0, width * 2.2] // zero-length dashes with round caps draw dots
        }
        thread.lineDashPattern = dashes?.map { NSNumber(value: Double($0)) }
        thread.shadowPath = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)

        // The string is drawn above the cards, so a small knot over each pin makes it look tied on.
        let radius = width * 1.3
        let knotPath = CGMutablePath()
        knotPath.addEllipse(in: CGRect(x: a.x - radius, y: a.y - radius, width: radius * 2, height: radius * 2))
        knotPath.addEllipse(in: CGRect(x: b.x - radius, y: b.y - radius, width: radius * 2, height: radius * 2))
        knots.path = knotPath
        knots.fillColor = color
    }
}
