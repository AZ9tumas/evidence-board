import Foundation
import QuartzCore
import BoardKit

/// How a string stands out while Focus or Trace is on.
enum StringEmphasis: Sendable {
    case normal
    /// Faded to about a quarter, without its label or shine.
    case dimmed
    /// On a traced path: a soft glow in its own color.
    case glowing
}

/// One string between two pins (DESIGN.md §4.5, §10.7).
///
/// At full detail the thread is a gradient running from one pin to the other, masked by the
/// curve, with a fiber texture, a soft shadow, knots over the pins, arrowheads and a glass
/// label at the middle. Further out it becomes a solid stroke, then a hairline. Every layer
/// draws in world coordinates, so moving a card only swaps paths.
@MainActor
final class StringNode {
    let id: UUID
    let layer = CALayer()
    private(set) var string: BoardString
    private(set) var curve = StringCurve(a: .zero, c1: .zero, c2: .zero, b: .zero)
    /// The curve as 16 straight pieces, for hit testing, arrowheads and the trace pulse.
    private(set) var polyline: [CGPoint] = []
    private(set) var length: CGFloat = 0
    /// A world-space box around everything the string draws.
    private(set) var hitBounds = CGRect.null
    /// Where the label capsule is, when the string has a label.
    private(set) var labelFrame: CGRect?
    var showsLabel: Bool { !label.isHidden }

    private let shadow = CALayer()
    private let halo = CAShapeLayer()
    private let thread = CAShapeLayer()
    private let gradient = CAGradientLayer()
    private let gradientMask = CAShapeLayer()
    private let fibers = CAShapeLayer()
    /// Arrowheads near the start and the end.
    private let arrows = [CAShapeLayer(), CAShapeLayer()]
    private let knots = [CAShapeLayer(), CAShapeLayer()]
    private let label = CAGradientLayer()
    private let labelDot = CAGradientLayer()
    private let labelText = CALayer()

    private var appearance: CanvasAppearance
    private var detail: DetailLevel
    private var zoom: CGFloat
    private var labelScale: CGFloat
    private var labelSize: (text: String, size: CGSize)?
    private var renderedLabel: (text: String, scale: CGFloat)?
    private var shadowIsStale = true
    private(set) var isSelected = false
    private(set) var emphasis = StringEmphasis.normal
    private var isEditingLabel = false

    init(string: BoardString, appearance: CanvasAppearance, detail: DetailLevel, zoom: CGFloat, scale: CGFloat, labelScale: CGFloat) {
        id = string.id
        self.string = string
        self.appearance = appearance
        self.detail = detail
        self.zoom = zoom
        self.labelScale = labelScale

        shadow.shadowColor = RGBA.black.cgColor
        shadow.shadowOpacity = 0.35
        shadow.shadowRadius = 2
        shadow.shadowOffset = CGSize(width: 0, height: 3)
        for shape in [halo, thread, gradientMask, fibers] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
        }
        gradientMask.strokeColor = RGBA.black.cgColor
        gradient.mask = gradientMask
        fibers.lineCap = .butt
        fibers.strokeColor = RGBA.white.opacity(0.25).cgColor

        label.startPoint = CGPoint(x: 0.5, y: 0)
        label.endPoint = CGPoint(x: 0.5, y: 1)
        label.shadowColor = RGBA.black.cgColor
        label.shadowOpacity = 0.4
        label.shadowRadius = 3
        label.shadowOffset = CGSize(width: 0, height: 2)
        labelDot.startPoint = CGPoint(x: 0, y: 0)
        labelDot.endPoint = CGPoint(x: 1, y: 1)
        labelDot.cornerRadius = StringLabelStyle.dot / 2
        label.addSublayer(labelDot)
        label.addSublayer(labelText)

        let stack: [CALayer] = [shadow, halo, thread, gradient, fibers, arrows[0], arrows[1], knots[0], knots[1], label]
        for item in stack { layer.addSublayer(item) }
        setContentsScale(scale)
    }

    func setContentsScale(_ scale: CGFloat) {
        let all: [CALayer] = [
            layer, shadow, halo, thread, gradient, gradientMask, fibers, label, labelDot,
            arrows[0], arrows[1], knots[0], knots[1],
        ]
        for item in all { item.contentsScale = scale }
    }

    // MARK: Updating

    /// Routes the string between two pins. `droopScale` above 1 adds slack, for the "pull
    /// taut" animation and the live string while connecting.
    func update(
        string: BoardString, from a: CGPoint, to b: CGPoint, fan: CGFloat,
        droopScale: CGFloat = 1, appearance: CanvasAppearance
    ) {
        if string.label != self.string.label || appearance != self.appearance { renderedLabel = nil }
        self.string = string
        self.appearance = appearance
        curve = CanvasGeometry.stringCurve(from: a, to: b, sag: CGFloat(string.sag), fan: fan, droopScale: droopScale)
        polyline = curve.flattened()
        length = CanvasGeometry.length(of: polyline)
        applyGeometry()
        applyStyle()
    }

    func setDetail(_ level: DetailLevel, zoom: CGFloat) {
        guard level != detail || zoom != self.zoom else { return }
        detail = level
        self.zoom = zoom
        applyStyle()
    }

    /// Pixels per point for the label text, which follows the zoom tier like card text.
    func setLabelScale(_ scale: CGFloat) {
        guard scale != labelScale else { return }
        labelScale = scale
        renderLabelIfNeeded()
    }

    func setSelected(_ selected: Bool) {
        guard selected != isSelected else { return }
        isSelected = selected
        applyStyle()
    }

    func setEmphasis(_ emphasis: StringEmphasis) {
        guard emphasis != self.emphasis else { return }
        self.emphasis = emphasis
        applyStyle()
    }

    /// While the label editor is open, the field replaces the capsule.
    func setEditingLabel(_ editing: Bool) {
        isEditingLabel = editing
        applyStyle()
    }

    // MARK: Geometry

    private func applyGeometry() {
        let path = curve.path
        let width = CGFloat(string.thickness)
        let box = curve.bounds.insetBy(dx: -(width * 2 + 12), dy: -(width * 2 + 12))
        for shape in [halo, thread, gradientMask, fibers] { shape.path = path }

        // The gradient runs from pin to pin. Its mask uses world coordinates inside the box.
        gradient.frame = box
        gradientMask.bounds = box
        gradientMask.position = CGPoint(x: box.width / 2, y: box.height / 2)
        gradient.startPoint = CGPoint(x: (curve.a.x - box.minX) / box.width, y: (curve.a.y - box.minY) / box.height)
        gradient.endPoint = CGPoint(x: (curve.b.x - box.minX) / box.width, y: (curve.b.y - box.minY) / box.height)
        shadow.bounds = box
        shadow.position = CGPoint(x: box.midX, y: box.midY)
        shadowIsStale = true

        // The string is drawn above the cards, so a small knot over each pin makes it look tied on.
        let radius = max(width * 1.3, 2.2)
        for (knot, point) in zip(knots, [curve.a, curve.b]) {
            knot.path = CGPath(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        }
        arrows[1].path = string.arrow == .none ? nil : arrowhead(at: polyline, width: width)
        arrows[0].path = string.arrow == .both ? arrowhead(at: polyline.reversed(), width: width) : nil

        hitBounds = box
        if let text = string.label, !text.isEmpty {
            let size = capsuleSize(for: text)
            let middle = curve.point(at: 0.5)
            let frame = CGRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height)
            labelFrame = frame
            hitBounds = hitBounds.union(frame)
            let bounds = CGRect(origin: .zero, size: size)
            label.bounds = bounds
            label.position = middle
            label.cornerRadius = size.height / 2
            label.shadowPath = CGPath(roundedRect: bounds, cornerWidth: size.height / 2, cornerHeight: size.height / 2, transform: nil)
            labelDot.frame = CGRect(
                x: StringLabelStyle.leading, y: (size.height - StringLabelStyle.dot) / 2,
                width: StringLabelStyle.dot, height: StringLabelStyle.dot
            )
            labelText.frame = StringLabelStyle.textRect(in: size)
        } else {
            labelFrame = nil
        }
    }

    private func capsuleSize(for text: String) -> CGSize {
        if let labelSize, labelSize.text == text { return labelSize.size }
        let size = StringLabelStyle.capsuleSize(for: text, appearance: appearance)
        labelSize = (text, size)
        return size
    }

    /// A notched arrowhead whose tip sits just clear of the pin at the end of `line`.
    private func arrowhead(at line: [CGPoint], width: CGFloat) -> CGPath? {
        guard let found = CanvasGeometry.point(on: line, distanceFromEnd: CanvasGeometry.pinDiameter / 2 + 3) else { return nil }
        let tip = found.point
        let direction = found.direction
        let size = 7 + width * 1.5
        let half = size * 0.55
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let base = CGPoint(x: tip.x - direction.dx * size, y: tip.y - direction.dy * size)
        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + normal.dx * half, y: base.y + normal.dy * half))
        path.addLine(to: CGPoint(x: base.x + direction.dx * size * 0.28, y: base.y + direction.dy * size * 0.28))
        path.addLine(to: CGPoint(x: base.x - normal.dx * half, y: base.y - normal.dy * half))
        path.closeSubpath()
        return path
    }

    // MARK: Style

    private func dashes(for width: CGFloat) -> [NSNumber]? {
        let lengths: [CGFloat]? = switch string.stroke {
        case .solid: nil
        case .dashed: [width * 3, width * 2.5]
        case .dotted: [0, width * 2.2] // zero-length dashes with round caps draw dots
        }
        return lengths?.map { NSNumber(value: Double($0)) }
    }

    private func applyStyle() {
        let width = CGFloat(string.thickness)
        let colors = appearance.gradient(for: string.color)
        let dimmed = emphasis == .dimmed
        let full = detail == .full && !dimmed
        let minimal = detail == .minimal
        let fade = dimmed ? 0.28 : 1
        let lineWidth = minimal ? max(width, 1 / zoom) : width
        let pattern = dashes(for: lineWidth)

        thread.isHidden = full
        thread.lineWidth = lineWidth
        thread.lineDashPattern = pattern
        thread.strokeColor = colors.from.opacity(colors.from.alpha * fade).cgColor

        gradient.isHidden = !full
        gradient.colors = colors.cgColors
        gradientMask.lineWidth = width
        gradientMask.lineDashPattern = pattern

        // Twisted-fiber highlights, only close enough to see them.
        fibers.isHidden = !full || zoom < 0.6 || string.stroke != .solid
        fibers.lineWidth = max(width * 0.45, 0.5)
        fibers.lineDashPattern = [NSNumber(value: Double(width * 0.5)), NSNumber(value: Double(width))]
        fibers.setAffineTransform(CGAffineTransform(translationX: 0, y: -width * 0.2))

        shadow.isHidden = !full || string.stroke == .dotted
        if !shadow.isHidden && shadowIsStale {
            var source = curve.path
            if string.stroke == .dashed, let pattern {
                source = source.copy(dashingWithPhase: 0, lengths: pattern.map { CGFloat($0.doubleValue) })
            }
            shadow.shadowPath = source.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
            shadowIsStale = false
        }

        for (index, color) in [colors.from, colors.to].enumerated() {
            let fill = color.opacity(color.alpha * fade).cgColor
            knots[index].fillColor = fill
            knots[index].isHidden = minimal
            arrows[index].fillColor = fill
            arrows[index].isHidden = minimal
        }

        if isSelected {
            halo.isHidden = false
            halo.strokeColor = appearance.selection.from.opacity(0.55).cgColor
            halo.lineWidth = width + 7 / zoom
        } else if emphasis == .glowing {
            halo.isHidden = false
            halo.strokeColor = colors.from.opacity(0.35).cgColor
            halo.lineWidth = width + 9 / zoom
        } else {
            halo.isHidden = true
        }

        label.isHidden = labelFrame == nil || detail != .full || dimmed || isEditingLabel
        label.colors = appearance.labelFill.cgColors
        label.borderColor = (isSelected ? appearance.selection.from : RGBA.white.opacity(0.16)).cgColor
        label.borderWidth = (isSelected ? 1.5 : 0.75) / zoom
        labelDot.colors = colors.cgColors
        renderLabelIfNeeded()
    }

    private func renderLabelIfNeeded() {
        guard !label.isHidden, let text = string.label, !text.isEmpty else { return }
        if let renderedLabel, renderedLabel.text == text, renderedLabel.scale == labelScale { return }
        labelText.contents = StringLabelStyle.render(text, size: labelText.bounds.size, scale: labelScale, appearance: appearance)
        labelText.contentsScale = labelScale
        renderedLabel = (text, labelScale)
    }

    // MARK: Animation (DESIGN.md §6.6)

    private var strokes: [CAShapeLayer] { [halo, thread, gradientMask, fibers] }
    private var decorations: [CALayer] { [knots[0], knots[1], arrows[0], arrows[1], label, shadow] }

    /// Draws the thread out from its first pin; the far knot, arrows and label follow.
    func animateDrawIn(duration: CFTimeInterval = 0.22) {
        for shape in strokes {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = duration
            draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shape.add(draw, forKey: "draw")
        }
        let now = CACurrentMediaTime()
        let followers: [CALayer] = [knots[1], arrows[0], arrows[1], label, shadow]
        for item in followers {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.beginTime = item.convertTime(now, from: nil) + duration * 0.7
            fade.duration = 0.15
            fade.fillMode = .backwards
            item.add(fade, forKey: "draw")
        }
    }

    /// Snaps: the thread shrinks toward its far end and everything else fades. The caller
    /// removes the layer afterwards.
    func animateRemoval(duration: CFTimeInterval = 0.15) {
        shrink(keyPath: "strokeStart", duration: duration)
    }

    /// Pulls the thread back into its first pin, for a connection that was let go.
    func animateRetraction(duration: CFTimeInterval = 0.18) {
        shrink(keyPath: "strokeEnd", duration: duration)
    }

    private func shrink(keyPath: String, duration: CFTimeInterval) {
        let from: Double = keyPath == "strokeStart" ? 0 : 1
        for shape in strokes {
            let snap = CABasicAnimation(keyPath: keyPath)
            snap.fromValue = from
            snap.toValue = 1 - from
            snap.duration = duration
            snap.timingFunction = CAMediaTimingFunction(name: .easeIn)
            snap.fillMode = .forwards
            snap.isRemovedOnCompletion = false
            shape.add(snap, forKey: "shrink")
        }
        for item in decorations {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = duration
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            item.add(fade, forKey: "shrink")
        }
    }
}
