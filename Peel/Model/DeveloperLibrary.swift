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

    /// The name of one of the environment's apps that is running, or nil when none is. Asked each time rather
    /// than stored, since an app can be opened while the page is on screen.
    func runningApp(of environment: DeveloperEnvironment) -> String? {
        environment.runningApp { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).lazy.compactMap(\.localizedName).first
        }
    }

    private func environment(of page: CarriedSelection.Page) -> DeveloperEnvironment? {
        environments?.first { $0.id == page.scope }
    }
}

extension DeveloperLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        (environments ?? []).compactMap { environment in
            let selected = environment.locations.filter { selectedURLs.contains($0.url) }
            guard !selected.isEmpty else { return nil }
            return CarriedSelection.Part(
                page: Tool.developer.page(environment.id),
                title: environment.name,
                source: environment.name,
                sourceKey: nil,
                sizes: Dictionary(selected.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    func appToQuit(for part: CarriedSelection.Part) -> String? {
        environment(of: part.page).flatMap(runningApp(of:))
    }

    /// Moves nothing while one of the environment's apps is open: files never move out from under a running app.
    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let environment = environment(of: part.page) else { return TrashResult() }
        guard runningApp(of: environment) == nil else { return nil }
        isRemoving = true
        defer { isRemoving = false }
        let urls = environment.locations.map(\.url).filter { selectedURLs.contains($0) && part.sizes.keys.contains($0) }
        return await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(urls)
    }

    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
        await refresh()
    }

    func choose(_ page: CarriedSelection.Page) {
        selection = page.scope
    }
}
