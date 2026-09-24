import Foundation
import Observation
import PeelCore

@Observable
final class FileSearchLibrary {
    var criteria = FileSearchCriteria()
    private(set) var results: FileSearchResults?
    private(set) var searchedCriteria: FileSearchCriteria?
    private(set) var isSearching = false
    private(set) var isRemoving = false
    var selectedURLs: Set<URL> = []
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

    func search() async {
        generation += 1
        let current = generation
        let criteria = criteria
        searchedCriteria = criteria
        guard criteria.isSearchable else {
            results = nil
            selectedURLs = []
            selectableURLs = []
            sizes = [:]
            isSearching = false
            return
        }
        isSearching = true
        let exclusions = ExclusionsStore.shared.exclusions
        let found = await FileSearch.run(criteria, exclusions: exclusions)
        guard current == generation else { return }
        results = found
        filteredBy = exclusions
        selectableURLs = Set(found.files.filter { !$0.requiresPrivileges && !$0.belongsToAnApp }.map(\.url))
        sizes = Dictionary(found.files.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
        selectedURLs.formIntersection(found.files.filter { !$0.requiresPrivileges }.map(\.url))
        isSearching = false
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
