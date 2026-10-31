public import Observation

/// Work that belongs to Peel rather than to a window, such as watching the folders apps are installed into, started
/// once and kept running while Peel does. Remove Peel pauses it before it moves Peel's files, since a folder watcher
/// or an update round going on would write them again, and resumes it when Peel stays where it was.
@MainActor
@Observable
public final class StandingWork {
    @ObservationIgnored private var work: [@MainActor () async -> Void] = []
    @ObservationIgnored private var running: [Task<Void, Never>] = []
    @ObservationIgnored private var stoppedWithIt: [@MainActor () -> Void] = []
    @ObservationIgnored private let scans: RunningScans

    public init(scans: RunningScans = .shared) {
        self.scans = scans
    }

    /// Starts each piece of work. Only the first call starts anything: a window built again calls it again.
    /// `stoppingWithIt` is work a person started that a pause stops as View > Stop does, and doesn't start again.
    public func start(_ work: [@MainActor () async -> Void], stoppingWithIt: [@MainActor () -> Void] = []) {
        guard self.work.isEmpty else { return }
        self.work = work
        self.stoppedWithIt = stoppingWithIt
        resume()
    }

    /// Stops every piece, every page's scan, and what `start` was given to stop with them. Each piece ends at its
    /// next wait, since a piece waits on something that ends when its task is canceled: a stream of changes, a
    /// notification, or a sleep.
    public func pause() {
        running.forEach { $0.cancel() }
        running = []
        scans.stopEvery()
        stoppedWithIt.forEach { $0() }
    }

    /// Starts every piece again after a pause.
    public func resume() {
        guard running.isEmpty else { return }
        running = work.map { piece in Task { await piece() } }
    }
}
