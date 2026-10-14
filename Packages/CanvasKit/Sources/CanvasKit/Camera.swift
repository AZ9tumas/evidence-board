import CoreGraphics
import Foundation
import BoardKit

/// Maps the infinite world plane onto the view.
///
/// `center` is the world point shown at the middle of the view. View coordinates have a
/// top-left origin with y growing downward, the same as world coordinates.
public struct Camera: Equatable, Sendable {
    public static let minZoom: CGFloat = 0.05
    public static let maxZoom: CGFloat = 8
    /// Stops used by Zoom In and Zoom Out.
    public static let zoomSteps: [CGFloat] = [0.05, 0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    public var center: CGPoint
    public private(set) var zoom: CGFloat

    public init(center: CGPoint = .zero, zoom: CGFloat = 1) {
        self.center = center
        self.zoom = Self.clamp(zoom)
    }

    public static func clamp(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return 1 }
        return min(max(zoom, minZoom), maxZoom)
    }

    // MARK: Conversions

    public func worldToView(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - center.x) * zoom + size.width / 2,
            y: (point.y - center.y) * zoom + size.height / 2
        )
    }

    public func viewToWorld(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - size.width / 2) / zoom + center.x,
            y: (point.y - size.height / 2) / zoom + center.y
        )
    }

    /// The world-to-view transform, applied to the whole world layer as one GPU matrix.
    public func transform(in size: CGSize) -> CGAffineTransform {
        CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: -center.x, y: -center.y)
    }

    public func visibleWorldRect(in size: CGSize) -> CGRect {
        let origin = viewToWorld(.zero, in: size)
        return CGRect(x: origin.x, y: origin.y, width: size.width / zoom, height: size.height / zoom)
    }

    // MARK: Moves

    /// Moves the content by `delta` view points, the way a drag or a two-finger scroll does.
    public mutating func pan(by delta: CGVector) {
        center.x -= delta.dx / zoom
        center.y -= delta.dy / zoom
    }

    /// The camera at `newZoom`, keeping the world point under `anchor` (a view point) fixed.
    public func zoomed(to newZoom: CGFloat, anchor: CGPoint, in size: CGSize) -> Camera {
        let pinned = viewToWorld(anchor, in: size)
        let zoom = Self.clamp(newZoom)
        let center = CGPoint(
            x: pinned.x - (anchor.x - size.width / 2) / zoom,
            y: pinned.y - (anchor.y - size.height / 2) / zoom
        )
        return Camera(center: center, zoom: zoom)
    }

    /// The next zoom stop above (or below) the current zoom.
    public func nextZoomStep(up: Bool) -> CGFloat {
        if up {
            return Self.zoomSteps.first { $0 > zoom * 1.01 } ?? Self.maxZoom
        } else {
            return Self.zoomSteps.last { $0 < zoom * 0.99 } ?? Self.minZoom
        }
    }

    /// A camera that shows all of `rect`, never zooming in past `maxZoom`.
    public static func fitting(_ rect: CGRect, in size: CGSize, padding: CGFloat = 80, maxZoom: CGFloat = 1) -> Camera {
        let width = max(size.width - padding * 2, 1)
        let height = max(size.height - padding * 2, 1)
        let zoom = min(width / max(rect.width, 1), height / max(rect.height, 1), maxZoom)
        return Camera(center: CGPoint(x: rect.midX, y: rect.midY), zoom: zoom)
    }

    /// In-between camera for animations. Zoom moves geometrically so every step feels the
    /// same size. With an `anchor`, that view point stays over the same world point throughout.
    public static func interpolate(
        from: Camera, to: Camera, progress t: CGFloat, anchor: CGPoint?, in size: CGSize
    ) -> Camera {
        if t <= 0 { return from }
        if t >= 1 { return to }
        let zoom = from.zoom * pow(to.zoom / from.zoom, t)
        if let anchor {
            return from.zoomed(to: zoom, anchor: anchor, in: size)
        }
        let center = CGPoint(
            x: from.center.x + (to.center.x - from.center.x) * t,
            y: from.center.y + (to.center.y - from.center.y) * t
        )
        return Camera(center: center, zoom: zoom)
    }
}

extension Camera {
    public init(viewport: Viewport) {
        self.init(center: CGPoint(x: viewport.x, y: viewport.y), zoom: viewport.zoom)
    }

    public var viewport: Viewport {
        Viewport(x: center.x, y: center.y, zoom: zoom)
    }
}
