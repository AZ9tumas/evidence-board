import AppKit
import QuartzCore

/// Draws card bitmaps a few at a time, within a small slice of each frame, so a burst of
/// newly visible cards never causes a dropped frame.
@MainActor
final class RenderQueue: NSObject {
    /// Main-thread time per frame spent drawing bitmaps: less while the camera moves, so a
    /// pan or zoom frame stays within its 4 ms budget (DESIGN.md §11).
    static let budget: CFTimeInterval = 0.005
    static let movingBudget: CFTimeInterval = 0.0015

    /// Whether the camera is moving right now.
    var isMoving: () -> Bool = { false }

    private weak var view: NSView?
    private var pending: [UUID] = []
    /// What one bitmap has taken lately, so a slice doesn't start one it can't finish.
    private var typicalCost: CFTimeInterval = 0.0005
    private var link: CADisplayLink?
    private let render: (UUID) -> Void

    init(view: NSView, render: @escaping (UUID) -> Void) {
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

    /// Draws for one frame's slice of time: at least one bitmap, then more while the next
    /// one is likely to fit.
    func runSlice() {
        var now = CACurrentMediaTime()
        let deadline = now + (isMoving() ? Self.movingBudget : Self.budget)
        var index = 0
        while index < pending.count, index == 0 || now + typicalCost < deadline {
            render(pending[index])
            index += 1
            let finished = CACurrentMediaTime()
            typicalCost += (finished - now - typicalCost) * 0.25
            now = finished
        }
        pending.removeFirst(index)
        if pending.isEmpty { stop() }
    }
}
