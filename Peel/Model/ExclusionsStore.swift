import Foundation
import Observation
import PeelCore

/// What the user told Peel to leave alone. Shared by every tool, so nothing excluded is ever scanned or removed.
@Observable
final class ExclusionsStore {
    static let shared = ExclusionsStore()

    private let store = ExclusionStore()
    private(set) var exclusions = Exclusions.notYetRead
    /// Incremented whenever the list changes. Pages scan again, or narrow their list, when it does, because
    /// what they show was filtered by the exclusions as they stood when the scan ran.
    private(set) var revision = 0
    /// The last change could not be written, so it will not be there after a relaunch.
    private(set) var couldNotSave = false
    /// The changes that could not be written. They stay in force until Peel quits, as Settings says, laid again
    /// over the list each time it is read, and the next change that is written takes them with it.
    @ObservationIgnored private var unsaved: [@Sendable (inout Exclusions) -> Void] = []
    /// The last read or change of the list, which the next one waits for, so they land in the order they were made.
    @ObservationIgnored private var last: Task<Void, Never>?
    /// The revision each page last scanned under. Kept here rather than in the page, because while Settings
    /// takes the whole pane, no page is on screen to notice a change.
    @ObservationIgnored private var scanned = ScannedRevisions()

    func needsRescan(_ page: String) -> Bool {
        scanned.needsRescan(page, at: revision)
    }

    /// Loads the saved list, at launch and whenever Peel comes forward, since `peel exclusions` can change it
    /// meanwhile. A page that scanned before it arrived filtered by nothing, so a loaded list that differs counts
    /// as a change.
    func load() async {
        await inTurn { [self] in show(withUnsaved(await store.load())) }
    }

    static func isTooBroad(_ url: URL) -> Bool {
        Exclusions.isTooBroad(url)
    }

    func add(paths: [URL]) async {
        await change { $0.add(paths) }
    }

    func add(bundleIdentifier: String) async {
        await change { $0.bundleIdentifiers.insert(bundleIdentifier) }
    }

    func remove(paths: [URL]) async {
        await change { $0.remove(paths) }
    }

    func remove(bundleIdentifiers: [String]) async {
        await change { $0.bundleIdentifiers.subtract(bundleIdentifiers) }
    }

    /// Replaces a list that could not be read, which the store keeps under another name.
    func startOver() async {
        await inTurn { [self] in
            couldNotSave = await !store.save(.none)
            guard !couldNotSave else { return }
            unsaved = []
            show(.none)
        }
    }

    /// Changes the saved list, which the store reads again under the file's lock, so a change made in Terminal
    /// meanwhile is kept. A change to a list that cannot be read starts a new one, as Settings says.
    private func change(_ transform: @escaping @Sendable (inout Exclusions) -> Void) async {
        await inTurn { [self] in
            let changes = unsaved + [transform]
            switch await store.change(startingOverIfUnreadable: true, { list in changes.forEach { $0(&list) } }) {
            case .saved(let saved):
                unsaved = []
                couldNotSave = false
                show(saved)
            case .notSaved(let changed):
                unsaved.append(transform)
                couldNotSave = true
                show(changed)
            case .unreadable:
                show(.unreadable)
            }
        }
    }

    /// Runs `operation` once the read or change before it has landed.
    private func inTurn(_ operation: @escaping () async -> Void) async {
        let previous = last
        let current = Task {
            await previous?.value
            await operation()
        }
        last = current
        await current.value
    }

    /// `list` with the changes that could not be written laid over it. They started a new list if the saved one
    /// could not be read.
    private func withUnsaved(_ list: Exclusions) -> Exclusions {
        guard !unsaved.isEmpty else { return list }
        var changed = list.isUnreadable ? .none : list
        unsaved.forEach { $0(&changed) }
        return changed
    }

    private func show(_ list: Exclusions) {
        guard list != exclusions else { return }
        exclusions = list
        revision += 1
    }
}
