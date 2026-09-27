@testable import PeelCore
import Testing

struct UpdateRoundsTests {
    /// A round started under the old update source keeps running for a while after the source changes. Its
    /// answers would overwrite what the new round learns, so none of them counts once the source has changed.
    @Test func aRoundFromBeforeTheSourceChangedCountsNothing() {
        var rounds = UpdateRounds<String>()
        let old = rounds.begin(["editor", "notes"])
        let before = rounds.answered("editor", in: old)
        #expect(before)

        rounds.sourceChanged()
        let new = rounds.begin(["editor", "notes"])
        let late = rounds.answered("notes", in: old)
        let current = rounds.answered("notes", in: new)
        #expect(!late)
        #expect(current)
        #expect(!rounds.isCurrent(old))
        #expect(rounds.isCurrent(new))
    }

    /// Two rounds can ask about the same app, as when a round starts while another still runs. The app is being
    /// checked until the last of them has its answer or ends.
    @Test func anAppIsCheckedUntilEveryRoundAskingAboutItIsDone() {
        var rounds = UpdateRounds<String>()
        let first = rounds.begin(["editor", "notes"])
        let second = rounds.begin(["editor"])
        #expect(rounds.checking == ["editor", "notes"])

        _ = rounds.answered("editor", in: first)
        #expect(rounds.checking == ["editor", "notes"])
        rounds.end(first)
        #expect(rounds.checking == ["editor"])
        rounds.end(second)
        #expect(rounds.checking.isEmpty)
    }
}
