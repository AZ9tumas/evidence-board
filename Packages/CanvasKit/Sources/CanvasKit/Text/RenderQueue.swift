import AppKit
import BoardKit
import QuartzCore

/// One card's text bitmap, described by value so it can be drawn away from the main thread.
struct BitmapJob: @unchecked Sendable {
    enum Kind {
        case text(TextPayload, size: CGSize, appearance: CanvasAppearance)
        case caption(String, overlay: Bool, size: CGSize, appearance: CanvasAppearance)
        /// The layout's attributed strings are made once and never changed.
        case web(WebCardLayout)
    }

    let kind: Kind
    let tier: CGFloat
    let scale: CGFloat
    /// The card's `textVersion` when this was made; a newer card won't take an old bitmap.
    let version: Int

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

/// Draws card bitmaps on background threads, a few at a time, and puts them on their cards
/// in a small slice of each frame, so a burst of newly visible cards never causes a dropped
/// frame (DESIGN.md §10.6).
@MainActor
final class RenderQueue: NSObject {
    /// Main-thread time per frame for starting and placing bitmaps: less while the camera
    /// moves, so a pan or zoom frame stays within its 4 ms budget (DESIGN.md §11).
    static let budget: CFTimeInterval = 0.004
    static let movingBudget: CFTimeInterval = 0.001
    /// Bitmaps being drawn at once. More would only draw cards that may have scrolled away.
    static let maxInFlight = 4

    /// Whether the camera is moving right now.
    var isMoving: () -> Bool = { false }

    private weak var view: NSView?
    private var pending: [UUID] = []
    private var inFlight: Set<UUID> = []
    private let finished = Finished()
    private var link: CADisplayLink?
    private let prepare: (UUID) -> BitmapJob?
    private let apply: (UUID, BitmapJob, CGImage?) -> Void
    private let drawing = DispatchQueue(label: "CanvasKit.bitmaps", qos: .userInitiated, attributes: .concurrent)

    /// `prepare` describes a card's bitmap, or returns nil when it needs none; `apply` puts a
    /// drawn bitmap on its card. Both run on the main thread.
    init(view: NSView, prepare: @escaping (UUID) -> BitmapJob?, apply: @escaping (UUID, BitmapJob, CGImage?) -> Void) {
        self.view = view
        self.prepare = prepare
        self.apply = apply
    }

    /// Nothing waiting, being drawn or waiting to be placed.
    var isEmpty: Bool { pending.isEmpty && inFlight.isEmpty && finished.isEmpty }

    /// Replaces the queue. `ids` should be ordered most important first.
    func schedule(_ ids: [UUID]) {
        pending = ids
        if isEmpty {
            stop()
        } else {
            start()
        }
    }

    /// Adds `ids` after what's already waiting, for cards that came into view mid-gesture.
    func enqueue(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let waiting = Set(pending)
        schedule(pending + ids.filter { !waiting.contains($0) })
    }

    private func start() {
        guard link == nil, let view else { return }
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Stops drawing. Bitmaps already being drawn are dropped when they finish.
    func stop() {
        link?.invalidate()
        link = nil
        pending = []
        inFlight = []
        _ = finished.takeAll()
    }

    @objc private func step(_ link: CADisplayLink) {
        runSlice()
    }

    /// One frame's work: place the bitmaps that are done, then start more while there's time.
    func runSlice() {
        let deadline = CACurrentMediaTime() + (isMoving() ? Self.movingBudget : Self.budget)
        for (id, job, image) in finished.takeAll() {
            guard inFlight.remove(id) != nil else { continue }
            apply(id, job, image)
        }
        var index = 0
        // Cards already being drawn wait their turn: the card may have changed since, and
        // then it needs drawing again.
        var later: [UUID] = []
        while index < pending.count, inFlight.count < Self.maxInFlight, CACurrentMediaTime() < deadline {
            let id = pending[index]
            index += 1
            if inFlight.contains(id) {
                later.append(id)
                continue
            }
            guard let job = prepare(id) else { continue }
            inFlight.insert(id)
            let finished = finished
            drawing.async {
                finished.append(id, job, job.draw())
            }
        }
        pending = later + pending.dropFirst(index)
        if isEmpty { stop() }
    }

    /// Bitmaps drawn in the background, waiting for the main thread.
    private final class Finished: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(UUID, BitmapJob, CGImage?)] = []

        var isEmpty: Bool { lock.withLock { items.isEmpty } }

        func append(_ id: UUID, _ job: BitmapJob, _ image: CGImage?) {
            lock.withLock { items.append((id, job, image)) }
        }

        func takeAll() -> [(UUID, BitmapJob, CGImage?)] {
            lock.withLock {
                defer { items = [] }
                return items
            }
        }
    }
}
