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
    private var choices = KeptSelection()

    var selectedEnvironment: DeveloperEnvironment? {
        environments?.first { $0.id == selection }
    }

    func refresh() async {
        guard
            let result = await scanRun.run({
                await DeveloperCaches.scan(exclusions: ExclusionsStore.shared.exclusions)
            })
        else { return }
        environments = result
        let locations = result.flatMap(\.locations)
        selectedURLs = choices.update(
            selectedURLs,
            selectable: Set(locations.map(\.url)),
            suggested: Set(locations.filter(\.isRecommended).map(\.url))
        )
        if let selection, !result.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    private func environment(of page: CarriedSelection.Page) -> DeveloperEnvironment? {
        environments?.first { $0.page == page }
    }
}

extension DeveloperEnvironment {
    var page: CarriedSelection.Page { Tool.developer.page(id) }
}

extension DeveloperLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        (environments ?? []).compactMap { environment in
            let selected = environment.locations.filter { selectedURLs.contains($0.url) }
            guard !selected.isEmpty else { return nil }
            return CarriedSelection.Part(
                page: environment.page,
                title: environment.name,
                source: environment.name,
                sourceKey: nil,
                sizes: Dictionary(selected.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    func appToQuit(for part: CarriedSelection.Part) -> String? {
        environment(of: part.page)?.runningApp
    }

    /// Moves nothing while one of the environment's apps is open: files never move out from under a running app.
    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let environment = environment(of: part.page) else { return TrashResult() }
        guard environment.runningApp == nil else { return nil }
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
