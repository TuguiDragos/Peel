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
    @ObservationIgnored private var canUseHelper = false

    var selectedItem: SpaceItem? {
        report?.items.first { $0.id == selection }
    }

    func refresh() async {
        await refresh(replanning: [])
    }

    /// Makes the area's plan from what is on disk now, keeping what was chosen in it.
    func plan(_ item: SpaceItem) async {
        let made = await newPlan(for: item)
        // A plan cut short measured only part of the area, and would read the rest as unknown.
        guard !Task.isCancelled else { return }
        keep(made.plan, for: item, madeWith: made.exclusions)
    }

    private func newPlan(for item: SpaceItem) async -> (plan: SpaceRemoval.Plan, exclusions: Int) {
        let revision = ExclusionsStore.shared.revision
        let plan = await SpaceRemoval.plan(
            for: item,
            exclusions: ExclusionsStore.shared.exclusions,
            running: RunningCopies.current
        )
        return (plan, revision)
    }

    private func keep(_ plan: SpaceRemoval.Plan, for item: SpaceItem, madeWith revision: Int) {
        let previous = plans[item.id]
        let chosen = plan.selection(keeping: selectedURLs, canUseHelper: canUseHelper)
        selectedURLs.subtract(previous?.removable ?? [])
        selectedURLs.formUnion(chosen)
        plans[item.id] = plan
        plannedFor[item.id] = (item, revision)
    }

    /// Makes the plans of the areas in `items` that have none yet, as the page's scan: Rescan turns into Stop
    /// meanwhile, and a scan that was stopped keeps no plan. True once every one of them has its plan.
    func planEvery(_ items: [SpaceItem]) async -> Bool {
        let unplanned = items.filter { !$0.isReadOnly && plans[$0.id] == nil }
        guard !unplanned.isEmpty else { return true }
        let answer = await scanRun.run {
            var made: [(item: SpaceItem, plan: SpaceRemoval.Plan, exclusions: Int)] = []
            for item in unplanned where !Task.isCancelled {
                let new = await self.newPlan(for: item)
                made.append((item, new.plan, new.exclusions))
            }
            return made
        }
        guard let made = answer else { return false }
        for (item, plan, revision) in made {
            keep(plan, for: item, madeWith: revision)
        }
        return true
    }

    /// Brings what is selected in each area in line with the helper as it is now, without measuring again.
    func follow(canUseHelper: Bool) {
        guard canUseHelper != self.canUseHelper else { return }
        self.canUseHelper = canUseHelper
        for plan in plans.values {
            let chosen = plan.selection(keeping: selectedURLs, canUseHelper: canUseHelper)
            selectedURLs.subtract(plan.removable)
            selectedURLs.formUnion(chosen)
        }
    }

    /// Scans again, and makes again the plans of the areas in `replanning` and of every area that changed since
    /// its plan was made, so what is carried from them follows what is on disk. The plans are part of the scan, so
    /// an area's page stays busy until it shows what is there now.
    private func refresh(replanning: Set<SpaceItem.ID>) async {
        let exclusions = ExclusionsStore.shared.exclusions
        let answer = await scanRun.run {
            let result = await SpaceInventory.scan(exclusions: exclusions)
            var made: [(item: SpaceItem, plan: SpaceRemoval.Plan, exclusions: Int)] = []
            for item in result.items where self.plans[item.id] != nil && !Task.isCancelled {
                let planned = self.plannedFor[item.id]
                let changed = planned?.item != item || planned?.exclusions != ExclusionsStore.shared.revision
                guard replanning.contains(item.id) || changed else { continue }
                let new = await self.newPlan(for: item)
                made.append((item, new.plan, new.exclusions))
            }
            return (result, made)
        }
        guard let (result, made) = answer else { return }
        report = result
        for id in plans.keys.filter({ id in !result.items.contains { $0.id == id } }) {
            selectedURLs.subtract(plans[id]?.removable ?? [])
            plans[id] = nil
            plannedFor[id] = nil
        }
        if let selection, !result.items.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        for (item, plan, revision) in made {
            keep(plan, for: item, madeWith: revision)
        }
    }
}

extension SpaceItem {
    var page: CarriedSelection.Page { Tool.space.page(id) }
}

extension SpaceLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        (report?.items ?? []).compactMap { item in
            guard let plan = plans[item.id] else { return nil }
            let selected = plan.removable.filter(selectedURLs.contains)
            guard !selected.isEmpty else { return nil }
            return CarriedSelection.Part(
                page: item.page,
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
        guard let item = report?.items.first(where: { $0.page == part.page }) else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let exclusions = ExclusionsStore.shared.exclusions
        let removable = await SpaceRemoval.removable(in: item, exclusions: exclusions, running: RunningCopies.current)
            .filter { selectedURLs.contains($0) && part.sizes.keys.contains($0) }
        return await TrashService(exclusions: exclusions)
            .trash(removable, usingHelperFor: Set(removable.filter(FileAccess.requiresPrivilegesToRemove)))
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
