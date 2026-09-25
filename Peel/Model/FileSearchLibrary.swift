import Foundation
import Observation
import PeelCore

@Observable
final class FileSearchLibrary {
    var criteria = FileSearchCriteria()
    private(set) var results: FileSearchResults?
    private(set) var searchedCriteria: FileSearchCriteria?
    /// The search this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    /// True while a search runs, and while one is due because the words changed since the last one was asked.
    /// Typing cancels the running search at once and starts the next a moment later, and the page stays busy
    /// between the two.
    var isSearching: Bool {
        scanRun.isRunning || (criteria.isSearchable && criteria != searchedCriteria)
    }
    private(set) var isRemoving = false
    var selectedURLs: Set<URL> = []
    /// The file the detail shows, chosen in the list. Checking a file for the Trash is `selectedURLs`, apart.
    var chosen: URL?
    /// The files Select All selects: not the ones that need an administrator, and not the ones an app keeps
    /// for itself, which stay listed with the reason beside them.
    private(set) var selectableURLs: Set<URL> = []
    private var sizes: [URL: Int64] = [:]
    private var generation = 0
    /// The exclusions the list is filtered by: those the search ran under, or those it was narrowed to since.
    private var filteredBy = Exclusions.none

    var selectedSize: Int64 {
        selectedURLs.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    var chosenFile: FoundFile? {
        results?.files.first { $0.url == chosen }
    }

    func search() async {
        generation += 1
        let current = generation
        let criteria = criteria
        searchedCriteria = criteria
        guard criteria.isSearchable else {
            // Nothing is asked of Spotlight anymore, so a search still running for the old words is stopped.
            scanRun.stop()
            results = nil
            selectedURLs = []
            selectableURLs = []
            sizes = [:]
            return
        }
        let exclusions = ExclusionsStore.shared.exclusions
        guard let found = await scanRun.run({ await FileSearch.run(criteria, exclusions: exclusions) }) else {
            // Canceled with the task that asked for it, as when the page goes away, the search answered nothing,
            // so the page asks again when it comes back. Stopped or replaced by a newer search, it counts as asked.
            if !scanRun.wasStopped, current == generation { searchedCriteria = nil }
            return
        }
        results = found
        filteredBy = exclusions
        selectableURLs = Set(found.files.filter { !$0.requiresPrivileges && !$0.belongsToAnApp }.map(\.url))
        sizes = Dictionary(found.files.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
        selectedURLs.formIntersection(found.files.filter { !$0.requiresPrivileges }.map(\.url))
        // The search ran under the exclusions as they were when it started, so leave out anything excluded since.
        await leaveOut(ExclusionsStore.shared.exclusions)
    }

    /// Narrows the list to what `exclusions` leave. File Search runs only when asked, so without this a file
    /// excluded from its own row would stay listed and selected until the move refused it.
    func leaveOut(_ exclusions: Exclusions) async {
        guard let results, exclusions != filteredBy else { return }
        let current = generation
        let kept = await Self.keeping(results.files, under: exclusions)
        guard current == generation else { return }
        filteredBy = exclusions
        guard kept.count < results.files.count else { return }
        let gone = Set(results.files.map(\.url)).subtracting(kept.map(\.url))
        self.results?.files = kept
        selectedURLs.subtract(gone)
        selectableURLs.subtract(gone)
        for url in gone {
            sizes[url] = nil
        }
    }

    /// Runs off the main actor, since checking each file resolves links on disk.
    @concurrent
    private static func keeping(_ files: [FoundFile], under exclusions: Exclusions) async -> [FoundFile] {
        exclusions.keeping(files, url: \.url)
    }

    /// Moves the selected files to the Trash. `record` writes History before the search runs again, since a
    /// Spotlight query can take a while and History is the way back for what just moved.
    func removeSelected(recording record: (TrashResult) async -> Void) async -> TrashResult {
        isRemoving = true
        defer { isRemoving = false }
        let files = results?.files.filter { selectedURLs.contains($0.url) && !$0.requiresPrivileges } ?? []
        let result = await FileSearch.trash(files, using: TrashService(exclusions: ExclusionsStore.shared.exclusions))
        await record(result)
        await search()
        return result
    }
}
