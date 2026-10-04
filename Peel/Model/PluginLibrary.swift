import Foundation
import Observation
import PeelCore

@Observable
final class PluginLibrary {
    private(set) var plugins: [Plugin]?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isRemoving = false
    var selection: Plugin.ID?

    var selectedPlugin: Plugin? {
        plugins?.first { $0.id == selection }
    }

    func refresh() async {
        guard let result = await scanRun.run({ await Plugins.scan(exclusions: ExclusionsStore.shared.exclusions) })
        else { return }
        plugins = result
        if let selection, !result.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func moveToTrash(_ plugin: Plugin, recording record: (TrashResult) async -> Void) async -> TrashResult {
        isRemoving = true
        defer { isRemoving = false }
        let privileged: Set<URL> = plugin.requiresPrivileges ? [plugin.url] : []
        let result = await QuitGuard.shared.run {
            let result = await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(
                [plugin.url],
                usingHelperFor: privileged
            )
            // Written down before the rescan, which can take a while: History is the way back for what just moved.
            await record(result)
            return result
        }
        await refresh()
        return result
    }
}
