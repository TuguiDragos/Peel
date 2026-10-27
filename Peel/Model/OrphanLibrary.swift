import AppKit
import Foundation
import Observation
import PeelCore

/// A page of Orphaned Files: what only an administrator can move, or a group.
enum OrphanPage: Hashable {
    case forAnAdministrator
    case group(OrphanGroup.ID)
}

@Observable
final class OrphanLibrary {
    private(set) var scan: OrphanScan?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isRemoving = false
    var selection: OrphanPage?
    var selectedURLs: Set<URL> = []

    /// The apps list the scan was checked against. The page scans again when the list changes.
    private(set) var scannedAgainst: AppLibrary.Listing?
    /// The groups the person said belong to an app, by identifier, with that app's bundle identifier, or nil when that
    /// list can't be read.
    private(set) var owners = OrphanOwners().load()

    var selectedGroup: OrphanGroup? {
        guard case .group(let id) = selection else { return nil }
        return scan?.groups.first { $0.id == id }
    }

    /// The pages the list shows, in its order.
    var pages: [OrphanPage] {
        guard let scan else { return [] }
        return (scan.forAnAdministrator.isEmpty ? [] : [.forAnAdministrator]) + scan.groups.map { .group($0.id) }
    }

    /// Takes out of the selection what waits for the helper while the helper can't act: its checkbox is off then, and
    /// a move would only refuse it, so it would stay selected, and counted, for every move after.
    func follow(canUseHelper: Bool) {
        let kept = Self.selection(selectedURLs, in: scan?.groups ?? [], canUseHelper: canUseHelper)
        if kept != selectedURLs { selectedURLs = kept }
    }

    static func selection(_ selected: Set<URL>, in groups: [OrphanGroup], canUseHelper: Bool) -> Set<URL> {
        guard !canUseHelper else { return selected }
        return selected.subtracting(groups.flatMap(\.items).filter { $0.isLocked(canUseHelper: false) }.map(\.url))
    }

    func selected(in group: OrphanGroup) -> [OrphanItem] {
        group.items.filter { selectedURLs.contains($0.url) }
    }

    func refresh(from library: AppLibrary) async {
        // An app that could not be read is missing from the list, and its files would look orphaned, so nothing is
        // listed until every app can be read.
        let listing = library.listing
        guard listing.readEverything else {
            scan = nil
            selection = nil
            selectedURLs = []
            scannedAgainst = listing
            return
        }
        // Until the apps are read, no folder has an owner, so every folder would look orphaned. The callers
        // check this too; checking here keeps a new caller from getting it wrong.
        guard !library.apps.isEmpty else { return }
        let installedApps = library.apps
        let owners = OrphanOwners().load()
        self.owners = owners
        guard let result = await scanRun.run({
            let remembered = await AppMemory().remember(installedApps)
            // What is currently running is better evidence than anything worked out from what is installed: a
            // helper or an agent can keep a folder that no app bundle claims.
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let scan = await OrphanScanner(exclusions: ExclusionsStore.shared.exclusions).scan(
                installedApps: installedApps,
                remembered: remembered,
                running: running,
                owners: owners ?? [:],
                leftForAnAdministrator: await LeftForAnAdministrator().load()
            )
            if !scan.appsOnOtherDisks.isEmpty {
                await AppMemory().remember(scan.appsOnOtherDisks)
            }
            return scan
        }), library.readEverything else { return }
        let remainingURLs = Set(result.groups.flatMap(\.items).filter { $0.leftAlone == nil }.map(\.url))
        scan = result
        scannedAgainst = listing
        selectedURLs.formIntersection(remainingURLs)
        if let selection, !pages.contains(selection) {
            self.selection = nil
        }
    }

    /// Takes `group` out of the list, as the person said it belongs to `app`. Nothing moves, and the group stays
    /// listed when the choice could not be saved, which answers false.
    func give(_ group: OrphanGroup, to app: InstalledApp) -> Bool {
        let saved = app.bundleIdentifier.map { OrphanOwners().give(group.identifier, to: $0) } ?? false
        owners = OrphanOwners().load()
        guard saved else { return false }
        if let scan {
            self.scan = scan.without(group.id)
        }
        selectedURLs.subtract(group.items.map(\.url))
        if selection == .group(group.id) { selection = nil }
        return true
    }

    /// Lists `groups` again, forgetting the app each was given to. False when that could not be saved.
    func forget(_ groups: [String], from library: AppLibrary) async -> Bool {
        guard OrphanOwners().take(groups) else {
            owners = OrphanOwners().load()
            return false
        }
        await refresh(from: library)
        return true
    }

    func startOwnersOver() -> StartOver {
        let answer = OrphanOwners().startOver()
        owners = OrphanOwners().load()
        return answer
    }
}

extension OrphanGroup {
    var page: CarriedSelection.Page { Tool.orphans.page(identifier) }
}

extension OrphanLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        Self.parts(of: scan?.groups ?? [], selecting: selectedURLs)
    }

    static func parts(of groups: [OrphanGroup], selecting selectedURLs: Set<URL>) -> [CarriedSelection.Part] {
        groups.compactMap { group in
            let selected = group.items.filter { selectedURLs.contains($0.url) }
            guard !selected.isEmpty else { return nil }
            return CarriedSelection.Part(
                page: group.page,
                title: group.title,
                source: group.title,
                sourceKey: nil,
                sizes: Dictionary(selected.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let group = scan?.groups.first(where: { $0.page == part.page }) else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let exclusions = ExclusionsStore.shared.exclusions
        return await OrphanRemoval.trash(
            selected(in: group).filter { part.sizes.keys.contains($0.url) },
            installedApps: apps.apps,
            remembered: await AppMemory().load(),
            scanner: OrphanScanner(exclusions: exclusions),
            using: TrashService(exclusions: exclusions),
            mayUseHelper: true
        )
    }

    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
        await refresh(from: apps)
    }

    func choose(_ page: CarriedSelection.Page) {
        selection = .group(page.scope)
    }
}
