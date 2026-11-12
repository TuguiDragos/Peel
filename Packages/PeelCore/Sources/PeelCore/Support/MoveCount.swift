import Synchronization

/// How many items a removal has taken so far (moved to the Trash, or downloads removed from iCloud Drive), so a long
/// one can say how far it got.
public final class MoveCount: Sendable {
    private let moved = Atomic<Int>(0)
    private let readings = Atomic<Int>(0)

    public init() {}

    public var value: Int { moved.load(ordering: .relaxed) }

    /// True while the removal reads again what it is about to move, before any of it moves.
    public var isReading: Bool { readings.load(ordering: .relaxed) > 0 }

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
