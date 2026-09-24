import Foundation
import Observation
import PeelCore

/// What the user told Peel to leave alone. Shared by every tool, so nothing excluded is ever scanned or removed.
@Observable
final class ExclusionsStore {
    static let shared = ExclusionsStore()

    private let store = ExclusionStore()
    private(set) var exclusions = Exclusions.none
    /// Incremented whenever the list changes. Pages scan again, or narrow their list, when it does, because
    /// what they show was filtered by the exclusions as they stood when the scan ran.
    private(set) var revision = 0
    /// The last change could not be written, so it will not be there after a relaunch.
    private(set) var couldNotSave = false
    private var hasLoaded = false
    /// The revision each page last scanned under. Kept here rather than in the page, because while Settings
    /// takes the whole pane, no page is on screen to notice a change.
    @ObservationIgnored private var scanned = ScannedRevisions()

    func needsRescan(_ page: String) -> Bool {
        scanned.needsRescan(page, at: revision)
    }

    /// Loads the saved list. A page that scanned before it arrived filtered by nothing, so a loaded list that
    /// differs counts as a change.
    func load() async {
        let loaded = await store.load()
        hasLoaded = true
        guard loaded != exclusions else { return }
        exclusions = loaded
        revision += 1
    }

    static func isTooBroad(_ url: URL) -> Bool {
        Exclusions.isTooBroad(url)
    }

    func add(paths: [URL]) async {
        var updated = await current()
        updated.paths.formUnion(paths.map { $0.standardizedFileURL })
        await save(updated)
    }

    func add(bundleIdentifier: String) async {
        var updated = await current()
        updated.bundleIdentifiers.insert(bundleIdentifier)
        await save(updated)
    }

    func remove(paths: [URL]) async {
        var updated = await current()
        updated.paths.subtract(paths.map { $0.standardizedFileURL })
        await save(updated)
    }

    func remove(bundleIdentifiers: [String]) async {
        var updated = await current()
        updated.bundleIdentifiers.subtract(bundleIdentifiers)
        await save(updated)
    }

    /// Replaces a list that could not be read, which the store keeps under another name.
    func startOver() async {
        await save(.none)
    }

    /// The list, loaded first if needed: a change made before the saved list is read would overwrite it.
    private func current() async -> Exclusions {
        if !hasLoaded { await load() }
        return exclusions
    }

    /// The last write, which the next one waits for. Writes land one at a time in the order they were made,
    /// so an older list can never overwrite a newer one.
    private var writing: Task<Void, Never>?

    private func save(_ updated: Exclusions) async {
        // Built anew, which clears `isUnreadable`, since the user has just edited the list.
        exclusions = Exclusions(paths: updated.paths, bundleIdentifiers: updated.bundleIdentifiers)
        revision += 1
        let saving = exclusions
        let previous = writing
        let write = Task { [store] in
            await previous?.value
            return await store.save(saving)
        }
        writing = Task { _ = await write.value }
        couldNotSave = await !write.value
    }
}
