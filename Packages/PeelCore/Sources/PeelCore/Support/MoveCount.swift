import Synchronization

/// How many items a removal has taken so far (moved to the Trash, or downloads removed from iCloud Drive), so a long
/// one can say how far it got.
public final class MoveCount: Sendable {
    private let moved = Atomic<Int>(0)

    public init() {}

    public var value: Int { moved.load(ordering: .relaxed) }

    func add(_ count: Int) {
        moved.wrappingAdd(count, ordering: .relaxed)
    }

    /// The count the removal in the current task adds to, set by whoever runs it.
    @TaskLocal public static var current: MoveCount?
}
