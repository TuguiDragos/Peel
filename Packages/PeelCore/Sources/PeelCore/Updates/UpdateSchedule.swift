public import Foundation

/// When to check an app for updates again.
///
/// Most apps answer "up to date" for months, and each answer costs a request to someone else's server. So
/// every answer that changes nothing doubles the wait, up to a week. A found update sets the wait back to a
/// day, because one release is often followed by another.
///
/// A feed that fails keeps a separate count, from 6 hours up to 2 days, since a server that is down may be
/// back soon. A long healthy wait says nothing about when a broken server recovers, so the counts stay apart.
///
/// The wait is only a minimum. Apps the user asks about, and bundles that changed on disk, are checked at once.
public struct UpdateSchedule: Sendable, Equatable, Codable {
    /// One day: the wait after an update is found, and where the doubling starts.
    public static let base: TimeInterval = 24 * 60 * 60
    public static let longest: TimeInterval = 7 * 24 * 60 * 60
    public static let afterFailure: TimeInterval = 6 * 60 * 60
    public static let longestAfterFailure: TimeInterval = 2 * 24 * 60 * 60

    /// The length of the wait, from the answer that set this schedule to `due`.
    public let wait: TimeInterval
    /// When it is worth asking again.
    public let due: Date
    /// Whether the answer that set this schedule was a failed check.
    public let isRetrying: Bool
    /// The healthy wait from before a run of failures, carried through them unchanged. During failures `wait`
    /// holds the failing count, so without this, one failed check would bring a weekly app back to every 2 days.
    public let healthyWait: TimeInterval?

    public static func next(
        after status: UpdateStatus,
        following previous: UpdateSchedule? = nil,
        from now: Date = .now
    ) -> UpdateSchedule {
        // An "up to date" found before the app was due (Rescan, or a bundle that changed) says nothing about how
        // often the app ships, so the wait stays the same and only restarts from `now`.
        if let previous, !previous.isDue(at: now), status == .upToDate, !previous.isRetrying {
            return UpdateSchedule(wait: previous.wait, due: now.addingTimeInterval(previous.wait), isRetrying: false, healthyWait: nil)
        }
        let wait = wait(after: status, following: previous)
        return UpdateSchedule(
            wait: wait,
            due: now.addingTimeInterval(wait),
            isRetrying: status == .failed,
            healthyWait: status == .failed ? healthyWait(before: previous) : nil
        )
    }

    private static func wait(after status: UpdateStatus, following previous: UpdateSchedule?) -> TimeInterval {
        switch status {
        case .updateAvailable:
            base
        case .upToDate:
            min(max(healthyWait(before: previous), base) * 2, longest)
        case .failed:
            min(max(failingWait(before: previous) * 2, afterFailure), longestAfterFailure)
        case .unsupported:
            // Nowhere to ask. What would change the answer is the app being replaced, and a bundle that
            // changes is checked at once whatever the wait says.
            longest
        }
    }

    /// Whether the app is due at `moment`. A due date further away than the wait can only come from a clock
    /// that was set back since, so it counts as due. Otherwise a check made with the clock a year ahead would
    /// silence every app for a year.
    public func isDue(at moment: Date = .now) -> Bool {
        due <= moment || due.timeIntervalSince(moment) > wait
    }

    /// The last healthy wait, which a run of failures does not change.
    private static func healthyWait(before previous: UpdateSchedule?) -> TimeInterval {
        guard let previous else { return base }
        return previous.isRetrying ? previous.healthyWait ?? base : previous.wait
    }

    /// The last failing wait. It starts at half of `afterFailure`, so the first doubling gives `afterFailure`.
    private static func failingWait(before previous: UpdateSchedule?) -> TimeInterval {
        guard let previous, previous.isRetrying else { return afterFailure / 2 }
        return previous.wait
    }
}
