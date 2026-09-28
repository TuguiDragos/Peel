/// Runs a piece of work one call at a time. A call made while it runs is not dropped, since it may bring news the
/// running one started too early to see: the work runs once more when it ends, however many calls came meanwhile.
@MainActor
public final class OneRunAtATime {
    private var isRunning = false
    private var isAskedAgain = false

    public init() {}

    public func run(_ work: () async -> Void) async {
        guard !isRunning else {
            isAskedAgain = true
            return
        }
        isRunning = true
        defer { isRunning = false }
        repeat {
            isAskedAgain = false
            await work()
        } while isAskedAgain
    }
}
