import Foundation
import Observation
import PeelCore

/// What Peel and `peel` have moved to the Trash since Peel was installed, as Home and the menu bar panel show it.
/// History adds to the totals whichever of the two records (`RemovalTotals`), so they are read, never counted here.
@Observable
final class LifetimeStats {
    private static let installedKey = "statsInstalledOn"

    /// Where the app kept its totals before `peel` counted too.
    private enum Earlier {
        static let bytes = "statsBytesFreed"
        static let bytesIncomplete = "statsBytesFreedIsIncomplete"
        static let items = "statsItemsRemoved"
        static let apps = "statsAppsRemoved"
        static let biggest = "statsBiggestCleanUp"
        static let biggestIncomplete = "statsBiggestCleanUpIsIncomplete"
        static let all = [bytes, bytesIncomplete, items, apps, biggest, biggestIncomplete]
    }

    private let defaults: UserDefaults
    private let history: URL

    private(set) var installedOn: Date
    private(set) var totals: RemovalTotals

    init(
        defaults: UserDefaults = .standard,
        bundle: URL = Bundle.main.bundleURL,
        history: URL = RemovalHistory.defaultURL
    ) {
        self.defaults = defaults
        self.history = history
        installedOn = defaults.object(forKey: Self.installedKey) as? Date ?? Self.arrival(of: bundle)
        totals = RemovalTotals.read(beside: history)
        defaults.set(installedOn, forKey: Self.installedKey)
    }

    var bytesFreed: SizeTotal { totals.bytes }
    var itemsRemoved: Int { totals.items }
    var appsRemoved: Int { totals.apps }
    var biggestCleanUp: SizeTotal { totals.biggest }

    /// True once Peel has removed something. Home shows the totals only then, so a new install does not show
    /// a row of zeros.
    var hasCleaned: Bool { itemsRemoved > 0 }

    /// True when the biggest cleanup differs from the total. While the two are equal, as after the first
    /// cleanup, showing both would say the same thing twice.
    var hasABiggestCleanUp: Bool { biggestCleanUp.known > 0 && biggestCleanUp != bytesFreed }

    /// Reads the totals again: after a removal, and whenever Peel comes forward, since `peel` adds to them too.
    func reload() {
        let read = RemovalTotals.read(beside: history)
        if read != totals {
            totals = read
        }
    }

    /// Adds the totals the app kept in its preferences to the shared ones, then forgets them there.
    func takeInEarlierTotals() async {
        guard defaults.object(forKey: Earlier.items) != nil else { return }
        // Any process can write these preferences, so a total below zero is read as none.
        let earlier = RemovalTotals(
            bytes: SizeTotal(
                known: max(0, Int64(defaults.integer(forKey: Earlier.bytes))),
                isComplete: !defaults.bool(forKey: Earlier.bytesIncomplete)
            ),
            items: max(0, defaults.integer(forKey: Earlier.items)),
            apps: max(0, defaults.integer(forKey: Earlier.apps)),
            biggest: SizeTotal(
                known: max(0, Int64(defaults.integer(forKey: Earlier.biggest))),
                isComplete: !defaults.bool(forKey: Earlier.biggestIncomplete)
            )
        )
        guard await RemovalLog(url: history).takeIn(earlier) else { return }
        Earlier.all.forEach(defaults.removeObject(forKey:))
        reload()
    }

    /// The date `bundle` was installed, which is the date it was added to its folder.
    ///
    /// `creationDate` is only a fallback: a bundle copied out of a disk image keeps the date its developer
    /// built it. The date is stored on first launch, because replacing the bundle for an update would
    /// otherwise move it forward.
    private static func arrival(of bundle: URL) -> Date {
        let values = try? bundle.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? .now
    }
}
