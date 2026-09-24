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

    /// The revision of the apps list the scan was checked against. The page scans again when the list changes.
    private(set) var scannedRevision: Int?

    var selectedGroup: OrphanGroup? {
        scan?.groups.first { $0.id == selection }
    }

    /// The selected items in `group`. Selections are kept across groups, but only the group on screen is
    /// counted or moved.
    func selected(in group: OrphanGroup) -> [OrphanItem] {
        group.items.filter { selectedURLs.contains($0.url) }
    }

    func refresh(from library: AppLibrary) async {
        // Until the apps are read, no folder has an owner, so every folder would look orphaned. The callers
        // check this too; checking here keeps a new caller from getting it wrong.
        guard !library.apps.isEmpty else { return }
        let (installedApps, revision) = (library.apps, library.revision)
        guard let result = await scanRun.run({
            let remembered = await AppMemory().remember(installedApps)
            // What is currently running is better evidence than anything worked out from what is installed: a
            // helper or an agent can keep a folder that no app bundle claims.
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            return await OrphanScanner(exclusions: ExclusionsStore.shared.exclusions)
                .scan(installedApps: installedApps, remembered: remembered, running: running)
        }) else { return }
        let remainingURLs = Set(result.groups.flatMap(\.items).filter { $0.leftAlone == nil }.map(\.url))
        scan = result
        scannedRevision = revision
        selectedURLs.formIntersection(remainingURLs)
        if let selection, !result.groups.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func removeSelected(in group: OrphanGroup, installedApps: [InstalledApp]) async -> TrashResult {
        isRemoving = true
        defer { isRemoving = false }
        let exclusions = ExclusionsStore.shared.exclusions
        return await OrphanRemoval.trash(
            selected(in: group),
            installedApps: installedApps,
            scanner: OrphanScanner(exclusions: exclusions),
            using: TrashService(exclusions: exclusions)
        )
    }
}
