import Foundation
import Testing

@testable import PeelCore

@Suite("Update schedule")
struct UpdateScheduleTests {
    private let moment = Date(timeIntervalSince1970: 1_000_000)

    @Test("An answer that changes nothing doubles the wait, and a week is where it stops")
    func upToDateBacksOff() {
        var schedule = UpdateSchedule.next(after: .upToDate, from: moment)
        #expect(schedule.wait == UpdateSchedule.base * 2)
        for _ in 0..<10 {
            schedule = UpdateSchedule.next(after: .upToDate, following: schedule, from: schedule.due)
        }
        #expect(schedule.wait == UpdateSchedule.longest)
    }

    @Test("An update found starts the count again, so the next release is not a week late")
    func anUpdateResetsTheWait() {
        var schedule = UpdateSchedule.next(after: .upToDate, from: moment)
        for _ in 0..<10 {
            schedule = UpdateSchedule.next(after: .upToDate, following: schedule, from: schedule.due)
        }
        let found = UpdateSchedule.next(after: .updateAvailable(version: "2.0"), following: schedule, from: moment)
        #expect(found.wait == UpdateSchedule.base)
    }

    @Test("A feed that fails is asked again in hours, however long the healthy wait had grown")
    func aFailureKeepsItsOwnCount() {
        var healthy = UpdateSchedule.next(after: .upToDate, from: moment)
        for _ in 0..<10 {
            healthy = UpdateSchedule.next(after: .upToDate, following: healthy, from: healthy.due)
        }
        #expect(healthy.wait == UpdateSchedule.longest)

        let first = UpdateSchedule.next(after: .failed, following: healthy, from: moment)
        #expect(first.wait == UpdateSchedule.afterFailure)
        #expect(first.isRetrying)
    }

    @Test("Failures double up to two days and stay there, rather than starting over at the ceiling")
    func theRetryCeilingHolds() {
        var schedule = UpdateSchedule.next(after: .failed, from: moment)
        var waits: [TimeInterval] = [schedule.wait]
        for _ in 0..<10 {
            schedule = UpdateSchedule.next(after: .failed, following: schedule, from: moment)
            waits.append(schedule.wait)
        }
        let hour: TimeInterval = 3600
        let expected: [TimeInterval] = [
            UpdateSchedule.afterFailure, 12 * hour, 24 * hour, UpdateSchedule.longestAfterFailure,
        ]
        #expect(Array(waits.prefix(4)) == expected)
        #expect(schedule.wait == UpdateSchedule.longestAfterFailure)
        #expect(waits.allSatisfy { $0 <= UpdateSchedule.longestAfterFailure })
    }

    /// Starts from the weekly ceiling, where a reset would show. From the first wait, a reset gives the same
    /// two days, and the test could not tell the difference.
    @Test("A spell of failures neither shortens nor lengthens the healthy count")
    func failuresDoNotDisturbTheHealthyCount() {
        var healthy = UpdateSchedule.next(after: .upToDate, from: moment)
        for _ in 0..<10 {
            healthy = UpdateSchedule.next(after: .upToDate, following: healthy, from: healthy.due)
        }
        #expect(healthy.wait == UpdateSchedule.longest)

        var failing = UpdateSchedule.next(after: .failed, following: healthy, from: healthy.due)
        failing = UpdateSchedule.next(after: .failed, following: failing, from: failing.due)
        let recovered = UpdateSchedule.next(after: .upToDate, following: failing, from: failing.due)

        #expect(recovered.wait == UpdateSchedule.longest, "one blip sent a weekly app back to every two days")
        #expect(!recovered.isRetrying)
    }

    /// A round run while the clock was a year ahead writes due dates a year away, and once the clock is set
    /// right no app would be checked for a year. A due date further off than its own wait can only come from a
    /// clock that moved back, so it counts as due.
    @Test("A due date further away than its own wait is not believed")
    func aDueDateFromAClockThatWasAheadIsDue() {
        let ahead = UpdateSchedule.next(after: .upToDate, from: moment.addingTimeInterval(365 * 86_400))
        #expect(ahead.isDue(at: moment))
        #expect(!UpdateSchedule.next(after: .upToDate, from: moment).isDue(at: moment.addingTimeInterval(60)))
    }

    /// Rescan asks at once, whatever the wait. Three such answers ten seconds apart say nothing about how
    /// often the app ships, so they keep the wait as it was.
    @Test("An answer that came before it was due does not lengthen the wait")
    func anAnswerAskedForEarlyKeepsTheWait() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let first = UpdateSchedule.next(after: .upToDate, from: now)
        var schedule = first
        for seconds in [10.0, 20, 30] {
            schedule = UpdateSchedule.next(after: .upToDate, following: schedule, from: now.addingTimeInterval(seconds))
        }

        #expect(schedule.wait == first.wait)
        #expect(schedule.due == now.addingTimeInterval(30 + first.wait))

        // Once the wait is over, an answer counts again and doubles the wait.
        let later = UpdateSchedule.next(after: .upToDate, following: schedule, from: schedule.due.addingTimeInterval(1))
        #expect(later.wait == first.wait * 2)
    }

    @Test("An app with nowhere to ask is left for a week")
    func nowhereToAsk() {
        #expect(UpdateSchedule.next(after: .unsupported, from: moment).wait == UpdateSchedule.longest)
    }

    @Test("Nothing waits longer than a week, and nothing is due before it was set")
    func theBounds() {
        let statuses: [UpdateStatus] = [.updateAvailable(version: "1"), .upToDate, .failed, .unsupported]
        var earlier: [UpdateSchedule?] = [nil]
        for status in statuses {
            earlier.append(UpdateSchedule.next(after: status, from: moment))
        }
        for status in statuses {
            for previous in earlier {
                let schedule = UpdateSchedule.next(after: status, following: previous, from: moment)
                #expect(schedule.wait > 0)
                #expect(schedule.wait <= UpdateSchedule.longest)
                #expect(schedule.due == moment.addingTimeInterval(schedule.wait))
                #expect(!schedule.isDue(at: moment))
                #expect(schedule.isDue(at: schedule.due))
            }
        }
    }

    @Test("A schedule survives being written down and read back")
    func itRoundTrips() throws {
        let schedule = UpdateSchedule.next(after: .failed, from: moment)
        let data = try JSONEncoder().encode(["com.example.app": schedule])
        let read = try JSONDecoder().decode([String: UpdateSchedule].self, from: data)
        #expect(read["com.example.app"] == schedule)
    }

    /// A failed round, such as one with no network, learns nothing, so an update known to be waiting stays known.
    @Test func aFailureDoesNotEraseAnUpdateThatWasWaiting() {
        let waiting = UpdateStatus.updateAvailable(version: "2.0")
        #expect(UpdateStatus.failed.following(waiting) == waiting)
        #expect(UpdateStatus.failed.following(.upToDate) == .failed)
        #expect(UpdateStatus.failed.following(nil) == .failed)
        #expect(UpdateStatus.upToDate.following(waiting) == .upToDate, "a real answer replaces what was known")
        #expect(UpdateStatus.updateAvailable(version: "3.0").following(waiting) == .updateAvailable(version: "3.0"))
    }
}
