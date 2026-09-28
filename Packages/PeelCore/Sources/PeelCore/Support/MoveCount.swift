import Synchronization

/// How many items a removal has moved so far, so a long one can say how far it got.
public final class MoveCount: Sendable {
    private let moved = Atomic<Int>(0)

    public init() {}

    public var value: Int { moved.load(ordering: .relaxed) }

    func add(_ count: Int) {
        moved.wrappingAdd(count, ordering: .relaxed)
    }

    /// The count that moves in the current task add to, set by whoever runs the removal.
    @TaskLocal public static var current: MoveCount?
}
