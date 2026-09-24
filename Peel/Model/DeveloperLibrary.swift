import AppKit
import Foundation
import Observation
import PeelCore

@Observable
final class DeveloperLibrary {
    private(set) var environments: [DeveloperEnvironment]?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isRemoving = false
    var selection: DeveloperEnvironment.ID?
    var selectedURLs: Set<URL> = []

    var selectedEnvironment: DeveloperEnvironment? {
        environments?.first { $0.id == selection }
    }

    func refresh() async {
        guard let result = await scanRun.run({ await DeveloperCaches.scan(exclusions: ExclusionsStore.shared.exclusions) }) else { return }
        // Selects only recommended locations new to this scan, so what the user deselected stays deselected.
        let previous = Set(environments?.flatMap(\.locations).map(\.url) ?? [])
        environments = result
        let locations = result.flatMap(\.locations)
        selectedURLs.formIntersection(Set(locations.map(\.url)))
        selectedURLs.formUnion(locations.filter { $0.isRecommended && !previous.contains($0.url) }.map(\.url))
        if let selection, !result.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    /// Whether one of the environment's apps is running. Asked each time rather than stored, since an app can
    /// be opened while the page is on screen.
    /// The name of one of the environment's apps that is running, or nil when none is.
    func runningApp(of environment: DeveloperEnvironment) -> String? {
        environment.runningApp { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).lazy.compactMap(\.localizedName).first
        }
    }

    /// Moves the selected locations of `environment` to the Trash. Returns nil, moving nothing, when one of its
    /// apps was opened between the button and the confirmation: files never move out from under a running app.
    func removeSelected(from environment: DeveloperEnvironment, recording record: (TrashResult) async -> Void) async -> TrashResult? {
        guard runningApp(of: environment) == nil else { return nil }
        isRemoving = true
        defer { isRemoving = false }
        let urls = environment.locations.map(\.url).filter(selectedURLs.contains)
        let result = await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(urls)
        // Written down before the rescan, which can take a while: History is the way back for what just moved.
        await record(result)
        await refresh()
        return result
    }
}
