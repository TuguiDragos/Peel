import Foundation
import Observation
import PeelCore

@Observable
final class PluginLibrary {
    private(set) var plugins: [Plugin]?
    /// The folders the last scan couldn't read, which may hold plug-ins it didn't list.
    private(set) var unreadable: [URL] = []
    private(set) var needsFullDiskAccess = false
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isRemoving = false
    var selection: Plugin.ID?
    private let scan: @MainActor (Exclusions) async -> PluginScan
    private let trashService: @MainActor (Exclusions) -> TrashService

    init(
        scan: @escaping @MainActor (Exclusions) async -> PluginScan = { await Plugins.scan(exclusions: $0) },
        trashService: @escaping @MainActor (Exclusions) -> TrashService = { TrashService(exclusions: $0) }
    ) {
        self.scan = scan
        self.trashService = trashService
    }

    var selectedPlugin: Plugin? {
        plugins?.first { $0.id == selection }
    }

    func refresh() async {
        let scan = scan
        guard let result = await scanRun.run({ await scan(ExclusionsStore.shared.exclusions) }) else { return }
        plugins = result.plugins
        unreadable = result.unreadable
        needsFullDiskAccess = result.needsFullDiskAccess
        if let selection, !result.plugins.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func moveToTrash(_ plugin: Plugin, recording record: (TrashResult) async -> Void) async -> TrashResult {
        isRemoving = true
        defer { isRemoving = false }
        let privileged: Set<URL> = plugin.requiresPrivileges ? [plugin.url] : []
        let service = trashService(ExclusionsStore.shared.exclusions)
        let result = await QuitGuard.shared.run {
            let result = await service.trash([plugin.url], usingHelperFor: privileged)
            await record(result)
            return result
        }
        // What moved leaves the list at once, so the page can say how the move went before the list, which can take
        // a while, is read again.
        let moved = Set(result.trashed.map(\.originalURL))
        plugins?.removeAll { moved.contains($0.url) }
        if let selection, moved.contains(selection) {
            self.selection = nil
        }
        return result
    }
}
