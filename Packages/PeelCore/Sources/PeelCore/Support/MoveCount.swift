import Synchronization

/// How many items a removal has taken so far (moved to the Trash, or downloads removed from iCloud Drive), so a long
/// one can say how far it got.
public final class MoveCount: Sendable {
    private let moved = Atomic<Int>(0)
    private let readings = Atomic<Int>(0)
    private let looked = Atomic<Int>(0)
    /// The number of the look running now (zero between looks), how many looks began, and the last one stopped.
    private let looking = Atomic<Int>(0)
    private let looks = Atomic<Int>(0)
    private let stoppedLook = Atomic<Int>(0)

    public init() {}

    public var value: Int { moved.load(ordering: .relaxed) }

    /// True while the removal reads again what it is about to move, before any of it moves.
    public var isReading: Bool { readings.load(ordering: .relaxed) > 0 }

    /// True while the guard looks through a folder too full for its look a scan makes, before that folder moves.
    public var isLooking: Bool { looking.load(ordering: .relaxed) != 0 }

    /// How many items the look running now has read.
    public var lookedAt: Int { looked.load(ordering: .relaxed) }

    /// True once the person stopped the look running now, which leaves its folder where it is.
    public var isStopped: Bool {
        let now = looking.load(ordering: .relaxed)
        return now != 0 && stoppedLook.load(ordering: .relaxed) == now
    }

    /// Stops the look running now, if one runs. The next folder too full is looked through as any other.
    public func stopLooking() {
        let now = looking.load(ordering: .relaxed)
        if now != 0 { stoppedLook.store(now, ordering: .relaxed) }
    }

    func addLooked(_ count: Int) {
        looked.wrappingAdd(count, ordering: .relaxed)
    }

    /// Runs `work`, the guard's look through one folder, as a look of its own, counted from zero. A move runs its
    /// looks one after another.
    func whileLooking<Answer>(_ work: () async -> Answer) async -> Answer {
        looked.store(0, ordering: .relaxed)
        looking.store(looks.wrappingAdd(1, ordering: .relaxed).newValue, ordering: .relaxed)
        defer { looking.store(0, ordering: .relaxed) }
        return await work()
    }

    func add(_ count: Int) {
        moved.wrappingAdd(count, ordering: .relaxed)
    }

    /// Runs `work`, a reading of what the removal in the current task is about to move, with `isReading` true.
    static func reading<Answer>(_ work: () async -> Answer) async -> Answer {
        guard let current else { return await work() }
        current.readings.wrappingAdd(1, ordering: .relaxed)
        defer { current.readings.wrappingSubtract(1, ordering: .relaxed) }
        return await work()
    }

    /// The count the removal in the current task adds to, set by whoever runs it.
    @TaskLocal public static var current: MoveCount?
}
