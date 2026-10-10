@testable import PeelCore
import Testing

struct OverlappingChecksTests {
    @Test func anAnswerShowsWhenItsCheckEndsThoughANewerCheckStarted() {
        var checks = OverlappingChecks()
        let first = checks.start()
        _ = checks.start()

        let shows = checks.mayShow(first)

        #expect(shows)
    }

    @Test func aNewerAnswerReplacesAnOlderOne() {
        var checks = OverlappingChecks()
        let first = checks.start()
        let second = checks.start()

        let shows = [checks.mayShow(first), checks.mayShow(second)]

        #expect(shows == [true, true])
    }

    @Test func anOlderAnswerNeverReplacesANewerOne() {
        var checks = OverlappingChecks()
        let first = checks.start()
        let second = checks.start()

        let shows = [checks.mayShow(second), checks.mayShow(first)]

        #expect(shows == [true, false])
    }

    @Test func aChangeLeavesOutWhatChecksStartedBeforeItFound() {
        var checks = OverlappingChecks()
        let before = checks.start()
        checks.changeStarts()
        checks.changeEnds()

        var shows = [checks.mayShow(before)]
        let after = checks.start()
        shows.append(checks.mayShow(after))

        #expect(shows == [false, true])
    }

    /// What a check finds while the helper is being repaired is neither the old helper nor the new one.
    @Test func noAnswerShowsWhileAChangeRuns() {
        var checks = OverlappingChecks()
        let before = checks.start()
        checks.changeStarts()
        let during = checks.start()

        var shows = [checks.mayShow(during), checks.mayShow(before)]
        checks.changeEnds()
        shows.append(checks.mayShow(during))
        let after = checks.start()
        shows.append(checks.mayShow(after))

        #expect(shows == [false, false, false, true])
    }

    /// Each check outlasts the start of the next, as Home's and Settings' did while the helper didn't answer.
    @Test func noAnswerWaitsForTheChecksToStopOverlapping() {
        var checks = OverlappingChecks()
        var running = [checks.start(), checks.start()]
        var shows: [Bool] = []
        for _ in 0..<4 {
            running.append(checks.start())
            shows.append(checks.mayShow(running.removeFirst()))
        }

        #expect(shows == [true, true, true, true])
    }
}
