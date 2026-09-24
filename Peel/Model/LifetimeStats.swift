import Foundation
import Observation
import PeelCore

/// Running totals of what Peel has removed since it was installed.
///
/// They are not worked out from History: that log is capped and drops whole batches once it is full, so a
/// total taken from it would go down over time. These counters only go up, and they are kept in the app's
/// user defaults rather than in the log.
@Observable
final class LifetimeStats {
    private enum Key {
        static let installed = "statsInstalledOn"
        static let bytes = "statsBytesFreed"
        static let bytesIncomplete = "statsBytesFreedIsIncomplete"
        static let items = "statsItemsRemoved"
        static let apps = "statsAppsRemoved"
        static let biggest = "statsBiggestCleanUp"
        static let biggestIncomplete = "statsBiggestCleanUpIsIncomplete"
    }

    private let defaults: UserDefaults

    private(set) var installedOn: Date
    /// Incomplete once a removal held something Peel could not measure: the total is then only the least it can be.
    private(set) var bytesFreed: SizeTotal
    private(set) var itemsRemoved: Int
    private(set) var appsRemoved: Int
    private(set) var biggestCleanUp: SizeTotal

    init(defaults: UserDefaults = .standard, bundle: URL = Bundle.main.bundleURL) {
        self.defaults = defaults
        installedOn = defaults.object(forKey: Key.installed) as? Date ?? Self.arrival(of: bundle)
        // Any process can write these preferences, so a total below zero is read as none, and every sum below
        // is capped rather than allowed to trap.
        bytesFreed = SizeTotal(known: max(0, Int64(defaults.integer(forKey: Key.bytes))), isComplete: !defaults.bool(forKey: Key.bytesIncomplete))
        itemsRemoved = max(0, defaults.integer(forKey: Key.items))
        appsRemoved = max(0, defaults.integer(forKey: Key.apps))
        biggestCleanUp = SizeTotal(known: max(0, Int64(defaults.integer(forKey: Key.biggest))), isComplete: !defaults.bool(forKey: Key.biggestIncomplete))
        defaults.set(installedOn, forKey: Key.installed)
    }

    /// True once Peel has removed something. Home shows the totals only then, so a new install does not show
    /// a row of zeros.
    var hasCleaned: Bool { itemsRemoved > 0 }

    /// True when the biggest cleanup differs from the total. While the two are equal, as after the first
    /// cleanup, showing both would say the same thing twice.
    var hasABiggestCleanUp: Bool { biggestCleanUp.known > 0 && biggestCleanUp != bytesFreed }

    /// The date `bundle` was installed, which is the date it was added to its folder.
    ///
    /// `creationDate` is only a fallback: a bundle copied out of a disk image keeps the date its developer
    /// built it. The date is stored on first launch, because replacing the bundle for an update would
    /// otherwise move it forward.
    private static func arrival(of bundle: URL) -> Date {
        let values = try? bundle.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? .now
    }

    /// Adds a removal to the totals. Apps are counted by the bundles that moved, not by batch: five apps
    /// removed together count as five, and an app reset, which moves settings but no bundle, counts as none. An
    /// item missing from `sizes` was not measured.
    func add(_ result: TrashResult, sizes: [URL: Int64]) {
        guard !result.trashed.isEmpty else { return }
        let freed = SizeTotal(result.trashed.map { sizes[$0.originalURL] })
        bytesFreed = SizeTotal(known: bytesFreed.known.addingCapped(freed.known), isComplete: bytesFreed.isComplete && freed.isComplete)
        itemsRemoved = itemsRemoved.addingCapped(result.trashed.count)
        // A helper app kept under a Library folder is a leftover, not an app the user removed.
        appsRemoved = appsRemoved.addingCapped(result.trashed.count { $0.originalURL.pathExtension.lowercased() == "app" && !$0.originalURL.pathComponents.contains("Library") })
        if freed.known > biggestCleanUp.known { biggestCleanUp = freed }

        defaults.set(Int(bytesFreed.known), forKey: Key.bytes)
        defaults.set(!bytesFreed.isComplete, forKey: Key.bytesIncomplete)
        defaults.set(itemsRemoved, forKey: Key.items)
        defaults.set(appsRemoved, forKey: Key.apps)
        defaults.set(Int(biggestCleanUp.known), forKey: Key.biggest)
        defaults.set(!biggestCleanUp.isComplete, forKey: Key.biggestIncomplete)
    }
}
