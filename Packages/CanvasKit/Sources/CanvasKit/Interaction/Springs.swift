import AppKit
import QuartzCore

/// Whether to tone motion down (DESIGN.md §6.6): springs become fades, pulses stop.
@MainActor
enum Motion {
    /// Shows full motion even with Reduce Motion on. Tests set it, and debug builds launched
    /// by the snapshot workflow (whose Mac has Reduce Motion on) start with it set.
    static var ignoresSystemSetting: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["EB_SNAPSHOT_SCENARIO"] != nil
        #else
        false
        #endif
    }()

    static var isReduced: Bool {
        !ignoresSystemSetting && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// A damped spring stepped by hand each frame, for motion that has to follow the pointer or
/// re-route a string as it moves (DESIGN.md §6.6). `response` is the period in seconds and
/// `damping` the damping ratio, as in SwiftUI's `.spring(response:dampingFraction:)`.
struct Spring: Sendable {
    var value: CGFloat
    var target: CGFloat
    var velocity: CGFloat = 0
    var response: CGFloat
    var damping: CGFloat
    /// Seconds to hold still before moving.
    var delay: CFTimeInterval = 0

    init(value: CGFloat, target: CGFloat, response: CGFloat, damping: CGFloat, delay: CFTimeInterval = 0) {
        self.value = value
        self.target = target
        self.response = response
        self.damping = damping
        self.delay = delay
    }

    mutating func step(_ dt: CFTimeInterval) {
        var remaining = dt
        if delay > 0 {
            let waited = min(delay, remaining)
            delay -= waited
            remaining -= waited
        }
        let omega = 2 * CGFloat.pi / max(response, 0.01)
        let stiffness = omega * omega
        let friction = 2 * damping * omega
        // Small fixed steps keep stiff springs stable at any frame rate.
        while remaining > 0 {
            let h = CGFloat(min(remaining, 1.0 / 240))
            velocity += (-stiffness * (value - target) - friction * velocity) * h
            value += velocity * h
            remaining -= CFTimeInterval(h)
        }
    }

    /// Settled within `tolerance` of the target and barely moving.
    func isSettled(tolerance: CGFloat = 0.001) -> Bool {
        delay <= 0 && abs(value - target) < tolerance && abs(velocity) < tolerance * 10
    }
}

/// Calls `onTick` with the frame's duration on every display refresh until it returns false.
@MainActor
final class FrameTicker: NSObject {
    var onTick: ((CFTimeInterval) -> Bool)?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    var isRunning: Bool { link != nil }

    func start(in view: NSView) {
        guard link == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = nil
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = min(max(now - (lastTimestamp ?? link.timestamp), 0), 1.0 / 30)
        lastTimestamp = now
        if onTick?(dt) != true { stop() }
    }
}
