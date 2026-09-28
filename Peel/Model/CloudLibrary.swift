import Foundation
import Observation
import PeelCore

@Observable
final class CloudLibrary {
    private(set) var files: [CloudFile]? {
        didSet {
            searchable = SearchableList(files ?? [], key: \.searchKey)
            lastMatch = nil
            sizes = Dictionary((files ?? []).map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            updateSelectedSize()
        }
    }
    @ObservationIgnored private var searchable = SearchableList<CloudFile>([], key: \.searchKey)
    /// The last search and what it found. A view asks again whenever it is drawn, a checkbox included.
    @ObservationIgnored private var lastMatch: (query: String, files: [CloudFile])?
    @ObservationIgnored private var sizes: [URL: Int64] = [:]
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isFreeing = false
    private(set) var refusals: [CloudRefusal] = []
    /// `wasCutShort`: there is more than the list shows. `couldNotRead`: iCloud Drive couldn't be read at all.
    private(set) var wasCutShort = false
    private(set) var couldNotRead = false
    var selectedURLs: Set<URL> = [] {
        didSet { updateSelectedSize() }
    }
    private(set) var selectedSize: Int64 = 0

    /// What the listed files take on this Mac, only the least it can be when there is more than the list shows.
    var total: SizeTotal {
        SizeTotal(known: (files ?? []).map(\.size).cappedSum, isComplete: !wasCutShort)
    }

    /// The files whose folder or path holds `query`, every file for an empty one.
    func files(matching query: String) -> [CloudFile] {
        guard files != nil else { return [] }
        if let lastMatch, lastMatch.query == query { return lastMatch.files }
        let found = searchable.matching(query)
        lastMatch = (query, found)
        return found
    }

    private func updateSelectedSize() {
        selectedSize = selectedURLs.map { sizes[$0] ?? 0 }.cappedSum
    }

    /// Scans again. What the last Free Up Space refused is cleared, since it described the old list.
    func refresh() async {
        refusals = []
        guard let scan = await scanRun.run({ await CloudStorage.downloaded(exclusions: ExclusionsStore.shared.exclusions) }) else { return }
        files = scan.files
        wasCutShort = scan.wasCutShort
        couldNotRead = scan.couldNotRead
        selectedURLs.formIntersection(Set(scan.files.map(\.url)))
    }

    /// Frees the local copies of the selected files and returns the bytes freed: the selection less what was
    /// refused. Nothing goes to the Trash, since each file stays in iCloud and there is nothing to put back.
    func freeSelected() async -> Int64 {
        isFreeing = true
        defer { isFreeing = false }
        let chosen = files?.filter { selectedURLs.contains($0.url) } ?? []
        let refused = await CloudStorage.free(chosen, exclusions: ExclusionsStore.shared.exclusions)
        let kept = Set(refused.map(\.url))
        await refresh()
        refusals = refused
        return chosen.filter { !kept.contains($0.url) }.map(\.size).cappedSum
    }
}
