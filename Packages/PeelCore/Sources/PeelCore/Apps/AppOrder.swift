public import Foundation

/// The sorting and filtering behind the Applications list, kept apart from the view that shows it.
public enum AppOrder {
    /// Sorts `apps` by `key`, largest first. Apps that tie are sorted by name, A to Z, so the list keeps a
    /// steady order while sizes are still loading.
    public static func sorted<Key: Comparable>(_ apps: [InstalledApp], descendingBy key: (InstalledApp) -> Key) -> [InstalledApp] {
        apps.sorted { lhs, rhs in
            let (left, right) = (key(lhs), key(rhs))
            if left != right { return left > right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Sorts `apps` by size, largest first. An app whose size could not be measured comes first, since it is most
    /// likely the biggest, and one still being measured comes last, after every size already known.
    public static func sortedBySize(_ apps: [InstalledApp], sizes: [URL: Int64], unmeasured: Set<URL>) -> [InstalledApp] {
        sorted(apps) { sizes[$0.id] ?? (unmeasured.contains($0.id) ? .max : -1) }
    }

    /// Whether `app` has not been opened in the last `months` months. An app with no record of being opened
    /// counts from the day it was added, since it is exactly the kind of app this filter is meant to find. An app
    /// whose openings nothing records, or one with neither date, does not count as unused.
    public static func isUnused(_ app: InstalledApp, forMonths months: Int, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard
            app.isUseRecorded,
            let last = app.lastUsedDate ?? app.dateAdded,
            let limit = calendar.date(byAdding: .month, value: -months, to: now)
        else { return false }
        return last < limit
    }
}
