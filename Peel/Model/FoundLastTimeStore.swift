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

    func record(_ looked: Looked, for tool: Tool) {
        found.record(count: looked.count, size: looked.size, for: tool.rawValue)
        defaults.set(found.data, forKey: Self.key)
    }
}

/// What a tool found when it looked, with no size for what has none, such as updates.
struct Looked: Equatable {
    let count: Int
    let size: SizeTotal?
}

// What counts as found for each tool Home lists. Each is nil until the tool has looked since Peel opened, so
// what an earlier look found stays until the tool looks again.

extension AppLibrary {
    /// The apps with an update waiting, as the menu bar counts them, once a round of checks is over.
    var looked: Looked? {
        hasLoaded && appsCheckingForUpdates.isEmpty ? Looked(count: menuBarUpdateCount, size: nil) : nil
    }
}

extension OrphanLibrary {
    /// The groups, sized by what Peel can move. What only an administrator can move is no group of Peel's to free.
    var looked: Looked? {
        scan.map { Looked(count: $0.groups.count, size: SizeTotal(combining: $0.groups.map(\.movable))) }
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
    var looked: Looked? {
        report.map { Looked(count: $0.items.count, size: SizeTotal(combining: $0.items.map(\.size))) }
    }
}

extension DeveloperLibrary {
    var looked: Looked? {
        environments.map { Looked(count: $0.count, size: SizeTotal(combining: $0.map(\.total))) }
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
        scan.map { Looked(count: $0.items.count, size: $0.items.movable) }
    }
}

extension DuplicateLibrary {
    var looked: Looked? {
        scan.map { scan in
            let reclaimable = (scan.groups.map(\.reclaimableSize) + scan.folderGroups.map(\.reclaimableSize)).cappedSum
            return Looked(
                count: scan.groups.count + scan.folderGroups.count,
                size: SizeTotal(known: reclaimable, isComplete: true)
            )
        }
    }
}

extension CloudLibrary {
    var looked: Looked? {
        guard let files, let total else { return nil }
        return Looked(count: files.count, size: total)
    }
}
