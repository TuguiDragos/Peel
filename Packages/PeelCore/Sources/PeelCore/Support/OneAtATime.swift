/// One piece of work at a time for one thing, such as a setting. A request made while work runs waits, and a newer
/// one takes its place, so only the latest runs next. The work learns whether another request waits, so it can leave
/// what only the last needs, such as restarting the Dock, to that one.
@MainActor
public final class OneAtATime<Value> {
    public typealias Work = @MainActor (Value, _ anotherWaits: () -> Bool) async -> Void

    private var isRunning = false
    private var waiting: (value: Value, work: Work)?
    private var askers: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Returns once `value` has run, or a newer request took its place and ran.
    public func ask(_ value: Value, work: @escaping Work) async {
        guard !isRunning else {
            await withCheckedContinuation { asker in
                waiting = (value, work)
                askers.append(asker)
            }
            return
        }
        isRunning = true
        var next: (value: Value, work: Work)? = (value, work)
        while let current = next {
            await current.work(current.value) { self.waiting != nil }
            next = waiting
            waiting = nil
        }
        isRunning = false
        let done = askers
        askers = []
        done.forEach { $0.resume() }
    }
}
