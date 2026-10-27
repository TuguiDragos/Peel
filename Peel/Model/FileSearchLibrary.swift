import Foundation
import Observation
import PeelCore

@Observable
final class FileSearchLibrary {
    var criteria = FileSearchCriteria()
    private(set) var results: FileSearchResults?
    private(set) var searchedCriteria: FileSearchCriteria?
    /// The criteria `results` answer.
    private var answered: FileSearchCriteria?
    let scanRun = ScanRun()
    /// True while a search runs, and while one is due because the words changed since the last was asked, so the
    /// page stays busy between two searches while someone types.
    var isSearching: Bool {
        scanRun.isRunning || (criteria.isSearchable && criteria != searchedCriteria)
    }
    private(set) var isRemoving = false
    var selectedURLs: Set<URL> = []
    /// The file the detail shows. The files selected for the Trash are `selectedURLs`.
    var chosen: URL?
    /// The files Peel recommends: not the ones that need an administrator, nor the ones an app keeps for itself.
    private(set) var recommendedURLs: Set<URL> = []
    /// The selected files a newer search no longer lists, which stay selected until the person deselects them.
    private(set) var selection = SearchSelection()
    /// True once the person chose to keep those files selected, until another search leaves out others.
    private(set) var keepsWhatIsOutside = false
    private var sizes: [URL: Int64] = [:]
    private var generation = 0
    /// The exclusions the list is filtered by: those the search ran under, or those it was narrowed to since.
    private var filteredBy = Exclusions.none
    private let run: @Sendable (FileSearchCriteria, Exclusions) async -> FileSearchResults

    init(
        run: @escaping @Sendable (FileSearchCriteria, Exclusions) async -> FileSearchResults = {
            await FileSearch.run($0, exclusions: $1)
        }
    ) {
        self.run = run
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
            scanRun.stop()
            forgetResults()
            return
        }
        let exclusions = ExclusionsStore.shared.exclusions
        let run = run
        guard let found = await scanRun.run({ await run(criteria, exclusions) }) else {
            // Canceled with the task that asked for it, as when the page goes away, the search answered nothing,
            // so the page asks again when it comes back. Stopped or replaced by a newer search, it counts as asked.
            if !scanRun.wasStopped, current == generation { searchedCriteria = nil }
            // Stopped, it leaves no list that answers other words than those now asked.
            if scanRun.wasStopped, current == generation, criteria != answered { forgetResults() }
            return
        }
        let known = results?.files ?? []
        results = found
        answered = criteria
        filteredBy = exclusions
        recommendedURLs = Set(found.files.filter { !$0.requiresPrivileges && !$0.belongsToAnApp }.map(\.url))
        let outsideBefore = Set(selection.outside.keys)
        selectedURLs = selection.update(selectedURLs, was: known, now: found.files)
        if Set(selection.outside.keys) != outsideBefore { keepsWhatIsOutside = false }
        sizes = Dictionary(
            (found.files + selection.outside.values).map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first }
        )
        // The search ran under the exclusions as they were when it started, so leave out anything excluded since.
        await leaveOut(ExclusionsStore.shared.exclusions)
    }

    private func forgetResults() {
        results = nil
        answered = nil
        selectedURLs = []
        selection = SearchSelection()
        recommendedURLs = []
        sizes = [:]
    }

    /// Keeps selected the files no longer listed, and stops saying so until another search leaves out others.
    func keepWhatIsOutside() {
        keepsWhatIsOutside = true
    }

    /// Deselects the files no longer listed.
    func deselectWhatIsOutside() {
        let outside = selection.outside.keys
        selectedURLs = selection.deselectOutside(from: selectedURLs)
        for url in outside {
            sizes[url] = nil
        }
    }

    /// Narrows the list to what `exclusions` leave. File Search runs only when asked, so without this a file
    /// excluded from its own row would stay listed and selected until the move refused it.
    func leaveOut(_ exclusions: Exclusions) async {
        guard let results, exclusions != filteredBy else { return }
        let current = generation
        let kept = await Self.keeping(results.files, under: exclusions)
        let outside = Array(selection.outside.values)
        let keptOutside = await Self.keeping(outside, under: exclusions)
        guard current == generation else { return }
        filteredBy = exclusions
        let goneOutside = Set(outside.map(\.url)).subtracting(keptOutside.map(\.url))
        selection.forget(goneOutside)
        selectedURLs.subtract(goneOutside)
        guard kept.count < results.files.count else { return }
        let gone = Set(results.files.map(\.url)).subtracting(kept.map(\.url))
        self.results?.files = kept
        self.results?.leftOut[.excluded, default: 0] += gone.count
        selectedURLs.subtract(gone)
        recommendedURLs.subtract(gone)
        for url in gone {
            sizes[url] = nil
        }
    }

    /// Runs off the main actor, since checking each file resolves links on disk.
    @concurrent
    private static func keeping(_ files: [FoundFile], under exclusions: Exclusions) async -> [FoundFile] {
        exclusions.keeping(files, url: \.url)
    }

}

extension FileSearchLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        guard !selectedURLs.isEmpty else { return [] }
        return [CarriedSelection.Part(
            page: Tool.fileSearch.page(),
            title: String(localized: Tool.fileSearch.title),
            source: Tool.fileSearch.title.inEnglish,
            sourceKey: "tool",
            sizes: Dictionary(uniqueKeysWithValues: selectedURLs.map { ($0, sizes[$0]) })
        )]
    }

    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        isRemoving = true
        defer { isRemoving = false }
        let files = ((results?.files ?? []) + selection.outside.values).filter {
            selectedURLs.contains($0.url) && part.sizes.keys.contains($0.url) && !$0.requiresPrivileges
        }
        return await FileSearch.trash(files, using: TrashService(exclusions: ExclusionsStore.shared.exclusions))
    }

    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
        await search()
    }
}
