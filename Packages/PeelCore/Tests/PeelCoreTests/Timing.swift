import Darwin

/// The processor time `work` takes on this thread, which other tests taking the processor do not stretch.
func processorTime(of work: () -> Void) -> Duration {
    let started = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    work()
    return .nanoseconds(Int64(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - started))
}

/// Runs `work` at user-initiated priority and times it where it returns. A task at the default priority resumes only
/// once every test queued before it has had a thread, and that wait would be counted too.
func timedWhereItRuns<Value: Sendable>(
    _ work: @escaping @Sendable () async -> Value
) async -> (value: Value, took: Duration) {
    await Task.detached(priority: .userInitiated) {
        let clock = ContinuousClock()
        let start = clock.now
        let value = await work()
        return (value, clock.now - start)
    }.value
}
