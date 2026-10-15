#if DEBUG
import Darwin
import Foundation

/// How long the app took from process start to its first board frame, written to the file
/// named by `EB_LAUNCH_LOG` so the snapshot workflow can check the launch budget
/// (DESIGN.md §11). Debug builds only.
enum LaunchTiming {
    @MainActor private static var recorded = false

    @MainActor
    static func recordFirstFrame() {
        guard !recorded, let path = ProcessInfo.processInfo.environment["EB_LAUNCH_LOG"], let start = processStart() else { return }
        recorded = true
        // The frame is committed at the end of this pass through the run loop.
        DispatchQueue.main.async {
            let milliseconds = Date().timeIntervalSince(start) * 1000
            try? String(format: "%.0f\n", milliseconds).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let time = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }
}
#endif
