import AppKit
import QuartzCore

/// Draws card bitmaps a few at a time, within a small slice of each frame, so a burst of
/// newly visible cards never causes a dropped frame.
@MainActor
final class RenderQueue: NSObject {
    /// Main-thread time per frame spent drawing bitmaps: less while the camera moves, so a
    /// pan or zoom frame stays within its 4 ms budget (DESIGN.md §11).
    static let budget: CFTimeInterval = 0.005
    static let movingBudget: CFTimeInterval = 0.0025

    /// Whether the camera is moving right now.
    var isMoving: () -> Bool = { false }

    private weak var view: NSView?
    private var pending: [UUID] = []
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

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        runSlice()
    }

    /// Draws for one frame's slice of time.
    func runSlice() {
        let deadline = CACurrentMediaTime() + (isMoving() ? Self.movingBudget : Self.budget)
        var index = 0
        while index < pending.count, CACurrentMediaTime() < deadline {
            render(pending[index])
            index += 1
        }
        pending.removeFirst(index)
        if pending.isEmpty { stop() }
    }
}
