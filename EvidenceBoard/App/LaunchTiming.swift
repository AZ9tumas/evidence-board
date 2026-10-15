import Darwin
import Foundation

/// How long the app took from process start to its first board frame, written to the file
/// named by `EB_LAUNCH_LOG` so the snapshot workflow can check the launch budget
/// (DESIGN.md §11). The first line is the total; the lines after it say when each step of
/// the launch was reached, to tell the system's share from the app's. Does nothing unless
/// that variable is set.
enum LaunchTiming {
    private static let path = ProcessInfo.processInfo.environment["EB_LAUNCH_LOG"]
    private static let lock = NSLock()
    nonisolated(unsafe) private static var marks: [(String, Double)] = []
    nonisolated(unsafe) private static var recorded = false

    static var isTiming: Bool { path != nil }

    /// Notes that the launch got to `step`, the first time it does. Safe from any thread.
    static func mark(_ step: String) {
        guard path != nil, let start = processStart else { return }
        let milliseconds = Date().timeIntervalSince(start) * 1000
        lock.withLock {
            guard !marks.contains(where: { $0.0 == step }) else { return }
            marks.append((step, milliseconds))
        }
    }

    @MainActor
    static func recordFirstFrame() {
        guard let path, let start = processStart else { return }
        let first = lock.withLock {
            defer { recorded = true }
            return !recorded
        }
        guard first else { return }
        // The frame is committed at the end of this pass through the run loop.
        DispatchQueue.main.async {
            let milliseconds = Date().timeIntervalSince(start) * 1000
            let steps = lock.withLock { marks }.sorted { $0.1 < $1.1 }.map { String(format: "%@: %.0f ms", $0.0, $0.1) }
            let text = ([String(format: "%.0f", milliseconds)] + steps + [String(format: "first frame: %.0f ms", milliseconds)])
                .joined(separator: "\n")
            try? (text + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static let processStart: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let time = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }()
}
