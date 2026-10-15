import Foundation

/// At most `total` fetches at once, and one per host (DESIGN.md §7.3).
actor FetchLimiter {
    let total: Int
    private var running = 0
    private var busyHosts: Set<String> = []
    private var waiting: [(host: String, continuation: CheckedContinuation<Void, Never>)] = []

    init(total: Int) {
        self.total = total
    }

    func acquire(host: String) async {
        if canStart(host) {
            start(host)
            return
        }
        await withCheckedContinuation { waiting.append((host, $0)) }
    }

    func release(host: String) {
        running -= 1
        busyHosts.remove(host)
        var index = 0
        while index < waiting.count, running < total {
            let next = waiting[index]
            if canStart(next.host) {
                waiting.remove(at: index)
                start(next.host)
                next.continuation.resume()
            } else {
                index += 1
            }
        }
    }

    private func canStart(_ host: String) -> Bool {
        running < total && !busyHosts.contains(host)
    }

    private func start(_ host: String) {
        running += 1
        busyHosts.insert(host)
    }
}
