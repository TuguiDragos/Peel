import Foundation
import Observation
import PeelCore

/// What each tool found the last time it looked, kept in the app's user defaults so the menu bar panel can list it.
@Observable
final class FoundLastTimeStore {
    private static let key = "home.foundLastTime"
    private let defaults: UserDefaults
    private(set) var found: FoundLastTime

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        found = FoundLastTime(data: defaults.data(forKey: Self.key))
    }

    /// The tools that found something, in the sidebar's order.
    var findings: [(tool: Tool, finding: FoundLastTime.Finding)] {
        Tool.allCases.compactMap { tool in found.findings[tool.rawValue].map { (tool, $0) } }
    }

    /// Each write makes every `AppStorage` in the app read again, and a look often finds what the last one did.
    func record(_ looked: Looked, for tool: Tool) {
        var next = found
        guard next.record(count: looked.count, size: looked.size, for: tool.rawValue) else { return }
        found = next
        defaults.set(found.data, forKey: Self.key)
    }
}

/// What a tool found when it looked, with no size for what has none, such as updates.
struct Looked: Equatable {
    let count: Int
    let size: SizeTotal?
}

// What counts as found for each tool the menu bar panel lists. Each is nil until the tool has looked since Peel
// opened, so what an earlier look found stays until the tool looks again.

extension OrphanLibrary {
    /// The groups, sized as the page sizes them: by what Peel can move now, with its helper or without it.
    func looked(canUseHelper: Bool) -> Looked? {
        scan.map { scan in
            let movable = scan.groups.map { $0.movable(canUseHelper: canUseHelper) }
            return Looked(count: scan.groups.count, size: SizeTotal(combining: movable))
        }
    }
}

extension IntelLibrary {
    var looked: Looked? {
        scan.map { Looked(count: $0.findings.count, size: nil) }
    }
}

extension HomebrewLibrary {
    var looked: Looked? {
        // With no Homebrew on the Mac, none of its updates is waiting.
        guard isInstalled else { return Looked(count: 0, size: nil) }
        return packages.map { Looked(count: $0.count(where: \.waitsForAnUpgrade), size: nil) }
    }
}

extension SpaceLibrary {
    /// No size: the areas overlap what Developer and iCloud Drive find, and Space never adds them up.
    var looked: Looked? {
        report.map { Looked(count: $0.items.count, size: nil) }
    }
}

extension DeveloperLibrary {
    /// The tools with something here: one whose folders are all kept elsewhere is no find.
    var looked: Looked? {
        environments.map { all in
            let found = all.filter { !$0.locations.isEmpty }
            return Looked(count: found.count, size: SizeTotal(combining: found.map(\.total)))
        }
    }
}

extension ProjectLibrary {
    var looked: Looked? {
        groups.map { Looked(count: $0.count, size: SizeTotal(combining: $0.map(\.total))) }
    }
}

extension InstallerLibrary {
    /// The items, sized by what Peel can move: a device backup is the app's that made it, and stays off the size.
    var looked: Looked? {
        scan.map { Looked(count: $0.items.count, size: $0.items.movable(canUseHelper: true)) }
    }
}

extension DuplicateLibrary {
    var looked: Looked? {
        scan.map { scan in
            let reclaimable = (scan.groups.map(\.reclaimableSize) + scan.folderGroups.map(\.reclaimableSize)).cappedSum
            return Looked(count: scan.groupsWithSomethingToMove, size: SizeTotal(known: reclaimable, isComplete: true))
        }
    }
}

extension CloudLibrary {
    var looked: Looked? {
        guard let files, let total else { return nil }
        return Looked(count: files.count, size: total)
    }
}
