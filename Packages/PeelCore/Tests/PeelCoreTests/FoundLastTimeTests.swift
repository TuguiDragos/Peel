import Foundation
@testable import PeelCore
import Testing

/// Home lists what each tool found the last time it looked, from what Peel kept in its preferences.
struct FoundLastTimeTests {
    private let monday = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let tuesday = Date(timeIntervalSinceReferenceDate: 800_086_400)

    @Test func keepsWhatEachToolFoundAcrossLaunches() {
        var found = FoundLastTime()
        found.record(count: 7, size: SizeTotal(known: 1_200_000, isComplete: true), for: "orphans", at: monday)
        found.record(count: 3, size: nil, for: "applications", at: tuesday)

        let read = FoundLastTime(data: found.data)

        #expect(read == found)
        #expect(
            read.findings["orphans"]
                == FoundLastTime.Finding(count: 7, size: SizeTotal(known: 1_200_000, isComplete: true), date: monday)
        )
        #expect(read.findings["applications"] == FoundLastTime.Finding(count: 3, size: nil, date: tuesday))
    }

    /// A total that left something unmeasured out is only the least it can be, and stays so.
    @Test func aSizeNotAllMeasuredStaysALowerBound() {
        var found = FoundLastTime()
        found.record(count: 2, size: SizeTotal(known: 500, isComplete: false), for: "developer", at: monday)

        #expect(FoundLastTime(data: found.data).findings["developer"]?.size == SizeTotal(known: 500, isComplete: false))
    }

    /// Looking again replaces what was found before, and finding nothing takes the tool off the list.
    @Test func aToolThatFindsNothingLeavesTheList() {
        var found = FoundLastTime()
        found.record(count: 7, size: nil, for: "orphans", at: monday)
        found.record(count: 4, size: nil, for: "orphans", at: tuesday)
        #expect(found.findings["orphans"] == FoundLastTime.Finding(count: 4, size: nil, date: tuesday))

        found.record(count: 0, size: SizeTotal(known: 0, isComplete: true), for: "orphans", at: tuesday)
        #expect(found.findings.isEmpty)
    }

    /// Any process can write an app's preferences, so an entry that makes no sense is left out, and the rest stay.
    @Test func readsNothingThatMakesNoSense() {
        let json = #"""
        {"orphans": {"count": -2, "date": 0}, "developer": {"count": 3, "bytes": -5, "date": 0},
         "cloud": "a word", "space": {"count": 2, "bytes": 10, "date": 0}}
        """#

        let read = FoundLastTime(data: Data(json.utf8))

        #expect(
            read.findings == [
                "space": FoundLastTime.Finding(
                    count: 2,
                    size: SizeTotal(known: 10, isComplete: true),
                    date: Date(timeIntervalSinceReferenceDate: 0)
                )
            ]
        )
        #expect(FoundLastTime(data: Data("not a list".utf8)).findings.isEmpty)
        #expect(FoundLastTime(data: nil).findings.isEmpty)
    }
}
