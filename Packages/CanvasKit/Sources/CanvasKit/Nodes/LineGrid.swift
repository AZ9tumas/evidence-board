import QuartzCore

/// The drafting grid behind a Blueprint board: hairlines every 24 pt with a heavier line
/// every fifth.
///
/// Like ``DotGrid`` it lives in view space and is stamped out by replicator layers, so a
/// camera move only changes a few properties. The pitch doubles when the lines would get
/// too dense, and the fine lines fade out when zoomed far out.
@MainActor
final class LineGrid {
    static let worldPitch: CGFloat = 24
    static let majorEvery: CGFloat = 5

    let layer = CALayer()
    private let minor = LineSet()
    private let major = LineSet()

    init() {
        layer.masksToBounds = true
        layer.addSublayer(minor.layer)
        layer.addSublayer(major.layer)
    }

    func setColor(_ color: RGBA) {
        minor.setColor(color)
        major.setColor(color.opacity(min(color.alpha * 2.2, 1)))
    }

    func setContentsScale(_ scale: CGFloat) {
        layer.contentsScale = scale
        minor.setContentsScale(scale)
        major.setContentsScale(scale)
    }

    func update(camera: Camera, viewSize size: CGSize, backingScale: CGFloat) {
        layer.frame = CGRect(origin: .zero, size: size)
        guard size.width > 0, size.height > 0 else { return }
        var worldPitch = Self.worldPitch
        while worldPitch * camera.zoom < DotGrid.minimumScreenPitch { worldPitch *= 2 }
        minor.layer.opacity = Float(DotGrid.opacity(forZoom: camera.zoom))
        let hairline = 1 / max(backingScale, 1)
        minor.update(camera: camera, worldPitch: worldPitch, size: size, lineWidth: hairline)
        major.update(camera: camera, worldPitch: worldPitch * Self.majorEvery, size: size, lineWidth: max(hairline, 1))
    }
}

/// One family of evenly spaced lines, across and down.
@MainActor
private final class LineSet {
    let layer = CALayer()
    private let columns = CAReplicatorLayer()
    private let rows = CAReplicatorLayer()
    private let vertical = CALayer()
    private let horizontal = CALayer()

    init() {
        layer.addSublayer(columns)
        layer.addSublayer(rows)
        columns.addSublayer(vertical)
        rows.addSublayer(horizontal)
    }

    func setColor(_ color: RGBA) {
        vertical.backgroundColor = color.cgColor
        horizontal.backgroundColor = color.cgColor
    }

    func setContentsScale(_ scale: CGFloat) {
        for item: CALayer in [layer, columns, rows, vertical, horizontal] { item.contentsScale = scale }
    }

    func update(camera: Camera, worldPitch: CGFloat, size: CGSize, lineWidth: CGFloat) {
        let frame = CGRect(origin: .zero, size: size)
        layer.frame = frame
        columns.frame = frame
        rows.frame = frame
        let screenPitch = worldPitch * camera.zoom
        let topLeft = camera.viewToWorld(.zero, in: size)
        let first = camera.worldToView(CGPoint(
            x: (topLeft.x / worldPitch).rounded(.down) * worldPitch,
            y: (topLeft.y / worldPitch).rounded(.down) * worldPitch
        ), in: size)

        vertical.frame = CGRect(x: first.x - lineWidth / 2, y: 0, width: lineWidth, height: size.height)
        columns.instanceCount = min(Int((size.width - first.x) / screenPitch) + 2, DotGrid.maximumInstances)
        columns.instanceTransform = CATransform3DMakeTranslation(screenPitch, 0, 0)

        horizontal.frame = CGRect(x: 0, y: first.y - lineWidth / 2, width: size.width, height: lineWidth)
        rows.instanceCount = min(Int((size.height - first.y) / screenPitch) + 2, DotGrid.maximumInstances)
        rows.instanceTransform = CATransform3DMakeTranslation(0, screenPitch, 0)
    }
}
