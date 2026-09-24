import Synchronization

/// How many files and folders a scan has read so far, shown while it runs instead of a progress bar. Most
/// scans cannot know how much is left to read, and a folder that does not answer would hold a bar still for
/// its whole budget. This count moves whenever anything is read.
public final class ScanCount: Sendable {
    private let read = Atomic<Int>(0)

    public init() {}

    public var value: Int { read.load(ordering: .relaxed) }

    func add(_ count: Int) {
        read.wrappingAdd(count, ordering: .relaxed)
    }

    /// The count that reads in the current task add to, set by whoever runs the scan. A walk on a thread of its
    /// own is handed it when it starts, since a task-local value does not follow work onto another thread.
    @TaskLocal public static var current: ScanCount?
}
