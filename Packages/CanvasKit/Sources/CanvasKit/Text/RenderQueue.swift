import AppKit
import BoardKit
import QuartzCore

/// One card's text bitmap, described by value.
struct BitmapJob {
    enum Kind {
        case text(TextPayload, size: CGSize, appearance: CanvasAppearance)
        case caption(String, overlay: Bool, size: CGSize, appearance: CanvasAppearance)
        case web(WebCardLayout)
    }

    let kind: Kind
    let tier: CGFloat
    let scale: CGFloat

    /// AppKit's text drawing must stay on the main thread: drawn on background threads it
    /// crashed inside AppKit on a real Mac (CI's Macs never hit it).
    @MainActor
    func draw() -> CGImage? {
        switch kind {
        case .text(let text, let size, let appearance):
            TextCardTypography.render(text, size: size, scale: scale, appearance: appearance)
        case .caption(let caption, let overlay, let size, let appearance):
            TextCardTypography.renderCaption(caption, overlay: overlay, size: size, scale: scale, appearance: appearance)
        case .web(let layout):
            WebCardTypography.render(layout, scale: scale)
        }
    }
}

/// Draws card bitmaps a few at a time, within a small slice of each frame, so a burst of
/// newly visible cards never causes a dropped frame (DESIGN.md §10.6).
@MainActor
final class RenderQueue: NSObject {
    /// Main-thread time per frame spent drawing bitmaps: less while the camera moves, so a
    /// pan or zoom frame stays within its 4 ms budget (DESIGN.md §11).
    static let budget: CFTimeInterval = 0.004
    static let movingBudget: CFTimeInterval = 0.001

    /// Whether the camera is moving right now.
    var isMoving: () -> Bool = { false }

    private weak var view: NSView?
    private var pending: [UUID] = []
    private var link: CADisplayLink?
    /// What one bitmap has taken lately, so a slice doesn't start one it can't finish.
    private var typicalCost: CFTimeInterval = 0.0005
    private let render: (UUID) -> Bool

    /// `render` draws one card's bitmap and puts it on the card, or returns false when the
    /// card needs none.
    init(view: NSView, render: @escaping (UUID) -> Bool) {
        self.view = view
        self.render = render
    }

    var isEmpty: Bool { pending.isEmpty }

    /// Replaces the queue. `ids` should be ordered most important first.
    func schedule(_ ids: [UUID]) {
        pending = ids
        if pending.isEmpty {
            stop()
        } else if link == nil, let view {
            let link = view.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    /// Adds `ids` after what's already waiting, for cards that came into view mid-gesture.
    func enqueue(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let waiting = Set(pending)
        schedule(pending + ids.filter { !waiting.contains($0) })
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        runSlice()
    }

    /// Draws for one frame's slice of time. At rest it always draws at least one bitmap.
    /// While the camera moves it starts only those its recent cost says will fit; the rest
    /// wait until the camera stops.
    func runSlice() {
        let moving = isMoving()
        var now = CACurrentMediaTime()
        let deadline = now + (moving ? Self.movingBudget : Self.budget)
        var index = 0
        while index < pending.count {
            if moving || index > 0, now + typicalCost > deadline { break }
            let drew = render(pending[index])
            index += 1
            let finished = CACurrentMediaTime()
            if drew { typicalCost += (finished - now - typicalCost) * 0.25 }
            now = finished
        }
        pending.removeFirst(index)
        if pending.isEmpty { stop() }
    }
}
