import AppKit
import Observation
import PeelCore

@Observable
final class CloudLibrary {
    private(set) var files: [CloudFile]? {
        didSet {
            lastMatch = nil
            lastFolders = nil
            sizes = Dictionary((files ?? []).map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            updateSelectedSize()
        }
    }
    @ObservationIgnored private var searchable = CloudFolder.searchable([], in: [])
    /// The last search and what it found. A view asks again whenever it is drawn, a checkbox included.
    @ObservationIgnored private var lastMatch: (query: String, files: [CloudFile])?
    @ObservationIgnored private var sizes: [URL: Int64] = [:]
    private(set) var folders: [CloudFolder] = [] {
        didSet { lastFolders = nil }
    }
    @ObservationIgnored private var lastFolders: (query: String, folders: [CloudFolder])?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isFreeing = false
    /// The downloads the running Remove Downloads has removed so far.
    let freeing = MoveProgress()
    @ObservationIgnored private var freeingTask: Task<CloudFreeing, Never>?
    private(set) var refusals: [CloudRefusal] = []
    /// `cutShort`: why there is more than the list shows. `couldNotRead`: iCloud Drive couldn't be read at all.
    private(set) var cutShort: CloudScan.CutShort?
    private(set) var couldNotRead = false
    /// The downloads left out because another copy on this Mac shares their space, so removing them frees nothing.
    private(set) var sharedDownloads = 0
    /// iCloud Drive was never set up for this account.
    private(set) var isNotSetUp = false
    var selectedURLs: Set<URL> = [] {
        didSet { updateSelectedSize() }
    }
    private(set) var selectedSize: Int64 = 0
    private let home: URL
    private let scan: @MainActor (URL, Exclusions, Set<URL>) async -> CloudScan
    private let removeDownloads: @MainActor ([CloudFile], Exclusions) async -> CloudFreeing

    init(
        home: URL = .homeDirectory,
        scan: @escaping @MainActor (URL, Exclusions, Set<URL>) async -> CloudScan = {
            await CloudStorage.downloaded(home: $0, exclusions: $1, desktopPictures: $2)
        },
        removeDownloads: @escaping @MainActor ([CloudFile], Exclusions) async -> CloudFreeing = {
            await CloudStorage.free($0, exclusions: $1)
        }
    ) {
        self.home = home
        self.scan = scan
        self.removeDownloads = removeDownloads
    }

    /// What the listed files take on this Mac, only the least it can be when there is more than the list shows, and
    /// nil until iCloud Drive has been read.
    var total: SizeTotal? {
        guard let files, !couldNotRead else { return nil }
        return SizeTotal(known: files.map(\.size).cappedSum, isComplete: cutShort == nil)
    }

    /// The files whose folder or path holds `query`, every file for an empty one.
    func files(matching query: String) -> [CloudFile] {
        guard files != nil else { return [] }
        if let lastMatch, lastMatch.query == query { return lastMatch.files }
        let found = searchable.matching(query)
        lastMatch = (query, found)
        return found
    }

    func folders(matching query: String) -> [CloudFolder] {
        guard !query.isEmpty else { return folders }
        if let lastFolders, lastFolders.query == query { return lastFolders.folders }
        let found = Set(files(matching: query).map(\.url))
        let narrowed = CloudFolder.ordered(folders.compactMap { $0.keeping(found) })
        lastFolders = (query, narrowed)
        return narrowed
    }

    private func updateSelectedSize() {
        selectedSize = selectedURLs.map { sizes[$0] ?? 0 }.cappedSum
    }

    /// Scans again. What the last Remove Downloads refused is cleared, since it described the old list.
    func refresh() async {
        refusals = []
        let pictures = Set(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) })
        let (home, scan) = (home, scan)
        guard
            let found = await scanRun.run({ await scan(home, ExclusionsStore.shared.exclusions, pictures) })
        else { return }
        folders = found.folders
        searchable = CloudFolder.searchable(found.files, in: found.folders)
        files = found.files
        cutShort = found.cutShort
        couldNotRead = found.couldNotRead
        sharedDownloads = found.sharedDownloads
        isNotSetUp = found.isNotSetUp
        selectedURLs.formIntersection(Set(found.files.map(\.url)))
    }

    /// Frees the local copies of the selected files and returns the bytes freed. Nothing goes to the Trash, since
    /// each file stays in iCloud and there is nothing to put back.
    func freeSelected() async -> Int64 {
        isFreeing = true
        defer { isFreeing = false }
        let chosen = files?.filter { selectedURLs.contains($0.url) } ?? []
        let exclusions = ExclusionsStore.shared.exclusions
        let removeDownloads = removeDownloads
        let task = Task { [freeing] in
            await freeing.run(toMove: chosen.count) { await removeDownloads(chosen, exclusions) }
        }
        freeingTask = task
        let done = await task.value
        freeingTask = nil
        await refresh()
        refusals = done.refused
        return done.freed.map(\.size).cappedSum
    }

    func stopFreeing() {
        freeingTask?.cancel()
    }
}
