public import Observation

/// The one scan a page runs at a time, held by the page's model so that it can be stopped from anywhere: the
/// toolbar, the View menu, or the page going away.
///
/// A new scan stops the one already running, since only the newest answer is wanted. Every scanner behind a
/// page is tested to return promptly when stopped and to read nothing more (`Unanswered` in the tests), so a
/// stopped scan does not keep walking the disk.
@MainActor
@Observable
public final class ScanRun {
    public private(set) var isRunning = false
    /// True when the last scan was stopped before it finished. The page then shows what the scan before it
    /// found, or says that nothing was read.
    public private(set) var wasStopped = false
    /// What the scan has read so far (`ScanCount`), brought up to date ten times a second while it runs.
    public private(set) var itemsRead = 0
    @ObservationIgnored private var newest = 0
    @ObservationIgnored private var stopNewest: (@Sendable () -> Void)?

    public init() {}

    /// Runs `work` as the page's scan and returns its answer, or nil when it was stopped, replaced by another
    /// scan, or canceled with its caller.
    public func run<Answer: Sendable>(_ work: @escaping @MainActor () async -> Answer) async -> Answer? {
        stopNewest?()
        newest += 1
        let asked = newest
        let count = ScanCount()
        let task = Task { await ScanCount.$current.withValue(count) { await work() } }
        stopNewest = { task.cancel() }
        wasStopped = false
        isRunning = true
        itemsRead = 0
        let reading = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, asked == self.newest else { return }
                self.itemsRead = count.value
            }
        }
        let answer = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        reading.cancel()
        guard asked == newest else { return nil }
        stopNewest = nil
        isRunning = false
        return task.isCancelled ? nil : answer
    }

    /// Stops the running scan. `isRunning` turns false at once, so the Rescan button comes back; the scan
    /// itself ends a moment later, and what it found is dropped.
    public func stop() {
        guard isRunning else { return }
        stopNewest?()
        stopNewest = nil
        newest += 1
        isRunning = false
        wasStopped = true
    }
}
