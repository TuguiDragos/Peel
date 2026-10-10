import Observation
import PeelCore

/// How far a removal has got, for the bar at the foot of the page while it runs.
@Observable
final class MoveProgress {
    private(set) var isMoving = false
    /// How many of `toMove` items have moved, brought up to date ten times a second while a move runs.
    private(set) var moved = 0
    private(set) var toMove = 0

    /// Runs `work`, counting each item a move in it takes to the Trash.
    func run<Result>(toMove count: Int, _ work: () async -> Result) async -> Result {
        isMoving = true
        moved = 0
        toMove = count
        let counted = MoveCount()
        let watching = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.moved = counted.value
            }
        }
        defer {
            watching.cancel()
            isMoving = false
        }
        return await MoveCount.$current.withValue(counted) { await work() }
    }
}
