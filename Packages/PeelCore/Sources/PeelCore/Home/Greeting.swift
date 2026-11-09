public import Foundation

public enum Greeting: String, Sendable, Hashable, CaseIterable {
    case morning
    case afternoon
    case evening
    /// All day on October 8, Peel's birthday, from its first in 2027.
    case birthday

    /// Midnight too, when Peel's birthday begins and ends.
    static let startHours = [0, 5, 12, 18]

    public static func at(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Greeting {
        if yearsOld(on: date, calendar: calendar) != nil { return .birthday }
        return switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<18: .afternoon
        default: .evening
        }
    }

    /// How old Peel turns on `date`, when it is October 8 of a year after 2026, the year its repository and its first
    /// release went public on that day. The day is the Gregorian one, which is when that happened, whatever calendar
    /// the Mac shows, and it begins and ends at midnight in the calendar's time zone.
    public static func yearsOld(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let day = gregorian.dateComponents([.year, .month, .day], from: date)
        guard day.month == 10, day.day == 8, let year = day.year, year > 2026 else { return nil }
        return year - 2026
    }

    /// The moments a greeting shown from `date` on is drawn again: then, and at every change after.
    public static func changes(
        from date: Date, calendar: Calendar = .autoupdatingCurrent
    ) -> some Sequence<Date> {
        sequence(first: date) { change(after: $0, calendar: calendar) }
    }

    /// When the greeting changes next.
    public static func change(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let changes = startHours.compactMap {
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: $0),
                matchingPolicy: .nextTime,
                direction: .forward
            )
        }
        return changes.min() ?? date.addingTimeInterval(3600)
    }
}
