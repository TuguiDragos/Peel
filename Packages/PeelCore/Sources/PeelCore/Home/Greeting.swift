public import Foundation

public enum Greeting: String, Sendable, Hashable, CaseIterable {
    case morning
    case afternoon
    case evening

    static let startHours = [5, 12, 18]

    public static func at(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Greeting {
        switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<18: .afternoon
        default: .evening
        }
    }

    /// When the greeting changes next, so a view can schedule its update.
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
