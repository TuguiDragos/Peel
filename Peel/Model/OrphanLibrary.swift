import AppKit
import Foundation
import Observation
import PeelCore

@Observable
final class OrphanLibrary {
    private(set) var scan: OrphanScan?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isRemoving = false
    var selection: OrphanGroup.ID?
    var selectedURLs: Set<URL> = []

    /// The apps list the scan was checked against. The page scans again when the list changes.
    private(set) var scannedAgainst: AppLibrary.Listing?
    /// The groups the person said belong to an app, by identifier, with that app's bundle identifier.
    private(set) var owners = OrphanOwners().load()

    var selectedGroup: OrphanGroup? {
        scan?.groups.first { $0.id == selection }
    }

    func selected(in group: OrphanGroup) -> [OrphanItem] {
        group.items.filter { selectedURLs.contains($0.url) }
    }

    func refresh(from library: AppLibrary) async {
        // An app that could not be read is missing from the list, and its files would look orphaned, so nothing is
        // listed until every app can be read.
        let listing = library.listing
        guard listing.unreadable.isEmpty else {
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
            return await OrphanScanner(exclusions: ExclusionsStore.shared.exclusions)
                .scan(installedApps: installedApps, remembered: remembered, running: running, owners: owners)
        }), library.unreadable.isEmpty else { return }
        let remainingURLs = Set(result.groups.flatMap(\.items).filter { $0.leftAlone == nil }.map(\.url))
        scan = result
        scannedAgainst = listing
        selectedURLs.formIntersection(remainingURLs)
        if let selection, !result.groups.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    /// Takes `group` out of the list, as the person said it belongs to `app`. Nothing moves, and the group stays
    /// listed when the choice could not be saved.
    func give(_ group: OrphanGroup, to app: InstalledApp) {
        guard OrphanOwners().give(group.identifier, to: app.bundleIdentifier), let scan else { return }
        owners[group.identifier.lowercased()] = app.bundleIdentifier
        self.scan = scan.without(group.id)
        selectedURLs.subtract(group.items.map(\.url))
        if selection == group.id { selection = nil }
    }

    /// Lists `groups` again, forgetting the app each was given to.
    func forget(_ groups: [String], from library: AppLibrary) async {
        guard OrphanOwners().take(groups) else { return }
        await refresh(from: library)
    }
}

extension OrphanLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        (scan?.groups ?? []).compactMap { group in
            let selected = selected(in: group)
            guard !selected.isEmpty else { return nil }
            return CarriedSelection.Part(
                page: Tool.orphans.page(group.identifier),
                title: group.title,
                source: group.identifier,
                sourceKey: nil,
                sizes: Dictionary(selected.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let group = scan?.groups.first(where: { $0.identifier == part.page.scope }) else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let exclusions = ExclusionsStore.shared.exclusions
        return await OrphanRemoval.trash(
            selected(in: group).filter { part.sizes.keys.contains($0.url) },
            installedApps: apps.apps,
            scanner: OrphanScanner(exclusions: exclusions),
            using: TrashService(exclusions: exclusions),
            mayUseHelper: true
        )
    }

    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
        await refresh(from: apps)
    }

    func choose(_ page: CarriedSelection.Page) {
        selection = page.scope
    }
}
