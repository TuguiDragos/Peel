import Observation
import PeelCore

/// How far a removal has got, for the bar at the foot of the page while it runs.
@Observable
final class MoveProgress {
    private(set) var isMoving = false
    /// How many of `toMove` items have moved, brought up to date ten times a second while a move runs.
    private(set) var moved = 0
    private(set) var toMove = 0
    /// True while the removal reads again what it is about to move, as Duplicates does, so nothing has moved yet.
    private(set) var isReading = false
    /// True while Peel looks through a folder too full for a quick look, before that folder moves.
    private(set) var isLooking = false
    /// How many items those looks have read.
    private(set) var lookedAt = 0
    private var counted: MoveCount?

    /// Runs `work`, counting each item a move in it takes to the Trash.
    func run<Result>(toMove count: Int, _ work: () async -> Result) async -> Result {
        isMoving = true
        moved = 0
        toMove = count
        isReading = false
        lookedAt = 0
        let counted = MoveCount()
        self.counted = counted
        let watching = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.moved = counted.value
                self?.isReading = counted.isReading
                self?.isLooking = counted.isLooking
                self?.lookedAt = counted.lookedAt
            }
        }
        defer {
            watching.cancel()
            isMoving = false
            isReading = false
            isLooking = false
            self.counted = nil
        }
        return await MoveCount.$current.withValue(counted) { await work() }
    }

    /// Stops the look through a folder, which then stays where it is.
    func stopLooking() {
        counted?.stopLooking()
    }
}
