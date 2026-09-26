import Foundation
import Observation
import PeelCore

@Observable
final class SpaceLibrary: RowSelection {
    private(set) var report: SpaceReport?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    var selection: SpaceItem.ID?
    /// What is selected inside the areas' folders.
    var selectedURLs: Set<URL> = []
    private(set) var isRemoving = false
    /// Each area's last plan: what its page lists, and what a selection carried from it is counted by.
    private(set) var plans: [SpaceItem.ID: SpaceRemoval.Plan] = [:]
    /// The area as it was, and the exclusions' revision, when its plan was made.
    @ObservationIgnored private var plannedFor: [SpaceItem.ID: (item: SpaceItem, exclusions: Int)] = [:]
    /// What was chosen in each area, kept through its plans.
    @ObservationIgnored private var choices: [SpaceItem.ID: KeptSelection] = [:]

    var selectedItem: SpaceItem? {
        report?.items.first { $0.id == selection }
    }

    func refresh() async {
        await refresh(replanning: [])
    }

    /// Makes the area's plan from what is on disk now, keeping what was chosen in it.
    func plan(_ item: SpaceItem) async {
        let revision = ExclusionsStore.shared.revision
        let plan = await SpaceRemoval.plan(
            for: item,
            exclusions: ExclusionsStore.shared.exclusions,
            running: SpaceRemoval.namesOfRunningApps()
        )
        // A plan cut short measured only part of the area, and would read the rest as unknown.
        guard !Task.isCancelled else { return }
        let previous = plans[item.id]
        let chosen = choices[item.id, default: KeptSelection()].update(
            selectedURLs,
            selectable: Set(plan.removable),
            suggested: plan.suggested
        )
        selectedURLs.subtract(previous?.removable ?? [])
        selectedURLs.formUnion(chosen)
        plans[item.id] = plan
        plannedFor[item.id] = (item, revision)
    }

    /// Scans again, and makes again the plans of the areas in `replanning` and of every area that changed since
    /// its plan was made, so what is carried from them follows what is on disk.
    private func refresh(replanning: Set<SpaceItem.ID>) async {
        guard let result = await scanRun.run({ await SpaceInventory.scan() }) else { return }
        report = result
        for id in plans.keys.filter({ id in !result.items.contains { $0.id == id } }) {
            selectedURLs.subtract(plans[id]?.removable ?? [])
            plans[id] = nil
            plannedFor[id] = nil
            choices[id] = nil
        }
        if let selection, !result.items.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        for item in result.items where plans[item.id] != nil {
            let made = plannedFor[item.id]
            if replanning.contains(item.id) || made?.item != item || made?.exclusions != ExclusionsStore.shared.revision {
                await plan(item)
            }
        }
    }
}

extension SpaceLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        (report?.items ?? []).compactMap { item in
            guard let plan = plans[item.id] else { return nil }
            let selected = plan.removable.filter(selectedURLs.contains)
            guard !selected.isEmpty else { return nil }
            return CarriedSelection.Part(
                page: Tool.space.page(item.id),
                title: String(localized: item.words.title),
                source: item.words.title.inEnglish,
                sourceKey: "space.\(item.id)",
                sizes: Dictionary(selected.map { ($0, plan.sizes[$0]) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    /// Asks the area again rather than trusting its plan: an app opened since may be writing to some of these
    /// folders, and they are left where they are.
    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let item = report?.items.first(where: { $0.id == part.page.scope }) else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let exclusions = ExclusionsStore.shared.exclusions
        let removable = await SpaceRemoval.removable(in: item, exclusions: exclusions, running: SpaceRemoval.namesOfRunningApps())
        return await TrashService(exclusions: exclusions)
            .trash(removable.filter { selectedURLs.contains($0) && part.sizes.keys.contains($0) })
    }

    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
        await refresh(replanning: Set(parts.map(\.page.scope)))
    }

    func choose(_ page: CarriedSelection.Page) {
        selection = page.scope
    }
}

extension SpaceItem.Category {
    var title: LocalizedStringResource {
        switch self {
        case .development: "Development"
        case .virtualMachines: "Virtual Machines"
        case .media: "Media and Backups"
        case .cloud: "Cloud Storage"
        case .library: "Your Library"
        }
    }

    var systemImage: String {
        switch self {
        case .development: "hammer"
        case .virtualMachines: "server.rack"
        case .media: "play.rectangle"
        case .cloud: "cloud"
        case .library: "books.vertical"
        }
    }
}
