import QuartzCore

/// The faint dot grid behind the board.
///
/// It is drawn in view space by two nested replicator layers, so the GPU stamps out every
/// dot and a camera move only changes a few properties. The pitch doubles whenever the dots
/// would get too dense, and the grid fades out when zoomed far out.
@MainActor
final class DotGrid {
    static let worldPitch: CGFloat = 24
    static let minimumScreenPitch: CGFloat = 14
    static let dotDiameter: CGFloat = 1.4
    static let maximumInstances = 600

    let layer = CALayer()
    private let rows = CAReplicatorLayer()
    private let columns = CAReplicatorLayer()
    private let dot = CALayer()

    init() {
        layer.masksToBounds = true
        layer.addSublayer(rows)
        rows.addSublayer(columns)
        columns.addSublayer(dot)
        dot.bounds = CGRect(x: 0, y: 0, width: Self.dotDiameter, height: Self.dotDiameter)
        dot.cornerRadius = Self.dotDiameter / 2
    }

    func setColor(_ color: RGBA) {
        dot.backgroundColor = color.cgColor
    }

    func setContentsScale(_ scale: CGFloat) {
        for item: CALayer in [layer, rows, columns, dot] { item.contentsScale = scale }
    }

    func update(camera: Camera, viewSize size: CGSize) {
        layer.frame = CGRect(origin: .zero, size: size)
        rows.frame = layer.bounds
        columns.frame = layer.bounds

        layer.opacity = Float(Self.opacity(forZoom: camera.zoom))
        guard layer.opacity > 0, size.width > 0, size.height > 0 else { return }

        var worldPitch = Self.worldPitch
        var screenPitch = worldPitch * camera.zoom
        while screenPitch < Self.minimumScreenPitch {
            worldPitch *= 2
            screenPitch *= 2
        }

        let topLeft = camera.viewToWorld(.zero, in: size)
        let firstWorld = CGPoint(
            x: (topLeft.x / worldPitch).rounded(.down) * worldPitch,
            y: (topLeft.y / worldPitch).rounded(.down) * worldPitch
        )
        let first = camera.worldToView(firstWorld, in: size)

        dot.position = first
        columns.instanceCount = min(Int((size.width - first.x) / screenPitch) + 2, Self.maximumInstances)
        columns.instanceTransform = CATransform3DMakeTranslation(screenPitch, 0, 0)
        rows.instanceCount = min(Int((size.height - first.y) / screenPitch) + 2, Self.maximumInstances)
        rows.instanceTransform = CATransform3DMakeTranslation(0, screenPitch, 0)
    }

    /// Fully visible from 40% zoom up, gone below 25%.
    nonisolated static func opacity(forZoom zoom: CGFloat) -> CGFloat {
        min(max((zoom - 0.25) / 0.15, 0), 1)
    }
}
