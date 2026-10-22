import Foundation

/// The pace of requests to one server: at most `limit` of them in any `window`, each waiting its turn. Apple says its
/// lookup "is limited to approximately 20 calls per minute", so a process asks the App Store no faster (`appStore`).
actor RequestWindow {
    /// The App Store's, which every check in the process shares.
    static let appStore = forTheAppStore()

    /// A window at the pace Apple gives for its lookup.
    static func forTheAppStore() -> RequestWindow {
        RequestWindow(limit: 20, window: .seconds(60))
    }

    private let limit: Int
    private let window: Duration
    private var sent: [ContinuousClock.Instant] = []

    init(limit: Int, window: Duration) {
        self.limit = limit
        self.window = window
    }

    /// Waits until a request may go, and counts it. A canceled wait throws, so nothing goes and nothing is counted.
    func turn() async throws {
        while true {
            let now = ContinuousClock.now
            sent.removeAll { now - $0 >= window }
            if sent.count < limit {
                sent.append(now)
                return
            }
            try await Task.sleep(until: sent[0] + window, clock: .continuous)
        }
    }
}
