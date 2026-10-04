import Foundation
import Observation
import PeelCore

enum DuplicateRow: Hashable {
    case folder(DuplicateFolderGroup.ID)
    case file(DuplicateGroup.ID)
}

@Observable
final class DuplicateLibrary {
    private static let foldersKey = "duplicateFolders"

    /// The folders to scan. It has no initial value, so what `init` reads is not saved again: only a change is,
    /// and the default folders stay a default until the user changes the list.
    var folders: [URL] {
        didSet {
            UserDefaults.standard.set(folders.map { $0.path(percentEncoded: false) }, forKey: Self.foldersKey)
        }
    }
    var kind = FileKind.any
    var minimumSize: Int64 = 100_000
    private(set) var scan: DuplicateScan? {
        didSet { readScan() }
    }
    /// The space each duplicate file frees, by path. Built once per scan, with `reclaimableFolders` and the
    /// counts below, so reading the selection's sizes doesn't walk the whole scan on every change.
    private(set) var reclaimable: [URL: Int64] = [:]
    private(set) var reclaimableFolders: [URL: Int64] = [:]
    private(set) var copyCount = 0
    private(set) var groupCount = 0
    private(set) var progress: DuplicateScanProgress?
    /// Whether the scan has reached its file step. Set by the first `.collecting`, which only the file step
    /// reports, or from the start when a kind is chosen, since folders are then not compared.
    private(set) var isOnFiles = false
    private(set) var isScanning = false
    private(set) var isRemoving = false
    var selection: DuplicateRow?
    private(set) var selectedURLs: Set<URL> = []
    private(set) var selectedFolders: Set<URL> = []
    /// What each selected copy frees, kept with the selection: a check changes one entry, so the move bar does not
    /// walk a selection that can reach a hundred thousand copies at every check.
    @ObservationIgnored private var selectedSizes: [URL: Int64?] = [:]
    /// The exclusions the list is filtered by: those the scan ran under, or those it was narrowed to since.
    private var filteredBy = Exclusions.none

    private var finder: DuplicateFinder { DuplicateFinder(exclusions: ExclusionsStore.shared.exclusions) }
    private var scanTask: Task<Void, Never>?
    /// Numbers each scan, so a stopped scan that finishes late can't replace a newer scan's results.
    private var generation = 0

    init() {
        if let paths = UserDefaults.standard.stringArray(forKey: Self.foldersKey) {
            folders = paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
        } else {
            folders = DuplicateFinder().defaultFolders
        }
    }

    var selectedGroup: DuplicateGroup? {
        guard case .file(let id) = selection else { return nil }
        return scan?.groups.first { $0.id == id }
    }

    var selectedFolderGroup: DuplicateFolderGroup? {
        guard case .folder(let id) = selection else { return nil }
        return scan?.folderGroups.first { $0.id == id }
    }

    var selectedCount: Int {
        selectedURLs.count + selectedFolders.count
    }

    private func readScan() {
        guard let scan else {
            reclaimable = [:]
            reclaimableFolders = [:]
            copyCount = 0
            groupCount = 0
            return
        }
        reclaimable = Dictionary(
            scan.groups.flatMap(\.files).map { ($0.url, $0.reclaimableSize) }
        ) { first, _ in first }
        reclaimableFolders = Dictionary(
            scan.folderGroups.flatMap(\.folders).map { ($0.url, $0.reclaimableSize) }
        ) { first, _ in first }
        copyCount =
            scan.groups.reduce(0) { $0 + $1.files.count } + scan.folderGroups.reduce(0) { $0 + $1.folders.count }
        groupCount = scan.groups.count + scan.folderGroups.count
    }

    /// Adds the folders Peel can scan and returns the others.
    func add(_ urls: [URL]) -> [URL] {
        for url in urls where finder.canScan(url) && !folders.contains(url) {
            folders.append(url)
        }
        return urls.filter { !finder.canScan($0) }
    }

    /// A scan clears the list, so none starts while a move to the Trash is taking what it lists.
    var canScan: Bool { !folders.isEmpty && !isRemoving }

    /// Starts a new scan. The previous one is canceled but not waited for, since a read stuck on a network
    /// share would hold back every later scan. Whatever it returns is dropped by its `generation`.
    func startScan() {
        guard canScan else { return }
        scanTask?.cancel()
        generation += 1
        let current = generation
        scanTask = Task { await runScan(current) }
    }

    /// Shows the scan stopped at once, as the other pages do. The scan itself ends a moment later, or once a read
    /// stuck on a network share returns, and what it found is dropped by its `generation`.
    func stop() {
        scanTask?.cancel()
        generation += 1
        progress = nil
        isScanning = false
    }

    func clearResults() {
        scan = nil
        selection = nil
        select([], folders: [])
    }

    /// Narrows the list to what `exclusions` leave. Duplicates scans only when asked, so without this a copy
    /// excluded from its own row would stay listed and selected until the move refused it.
    func leaveOut(_ exclusions: Exclusions) async {
        guard let scan, exclusions != filteredBy else { return }
        let current = generation
        let excluded = await scan.excluded(by: exclusions)
        guard current == generation, let latest = self.scan else { return }
        filteredBy = exclusions
        guard !excluded.isEmpty else { return }
        let remaining = latest.removing(excluded)
        self.scan = remaining
        select(remaining.keepingOneOfEach(selectedURLs), folders: remaining.keepingOneOfEachFolder(selectedFolders))
        if let selection, !remaining.holds(selection) {
            self.selection = nil
        }
    }

    private func runScan(_ current: Int) async {
        clearResults()
        isScanning = true
        progress = nil
        isOnFiles = kind != .any
        var options = DuplicateScanOptions(folders: folders)
        options.kind = kind
        options.minimumSize = minimumSize
        let exclusions = ExclusionsStore.shared.exclusions

        let (updates, continuation) = AsyncStream.makeStream(
            of: DuplicateScanProgress.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let progressUpdates = Task {
            for await update in updates {
                // A scan stopped or replaced reports on until it notices, over the newer scan's progress otherwise.
                guard current == generation else { break }
                if case .collecting = update {
                    isOnFiles = true
                }
                progress = update
            }
        }
        do {
            let result = try await DuplicateFinder(exclusions: exclusions, digestMemory: DigestMemory())
                .scan(options) { continuation.yield($0) }
            guard current == generation else { return }
            scan = result
            filteredBy = exclusions
            select(result.suggestedSelection, folders: result.suggestedFolderSelection)
        } catch {}
        continuation.finish()
        await progressUpdates.value
        guard current == generation else { return }
        progress = nil
        isScanning = false
        // The scan ran under the exclusions as they were when it started, so leave out anything excluded since.
        await leaveOut(ExclusionsStore.shared.exclusions)
    }

    func isSelected(_ file: DuplicateFile) -> Bool {
        selectedURLs.contains(file.url)
    }

    func canChange(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        DuplicateScan.canChange(file.url, among: group.files.map(\.url), selected: selectedURLs)
    }

    /// Changes nothing that would leave the group with no copy.
    func setSelected(_ isSelected: Bool, _ file: DuplicateFile, in group: DuplicateGroup) {
        guard canChange(file, in: group) else { return }
        if isSelected {
            selectedURLs.insert(file.url)
            selectedSizes.updateValue(reclaimable[file.url], forKey: file.url)
        } else {
            unselect([file.url])
        }
    }

    /// What the selection in `group` would free.
    func selectedSize(in group: DuplicateGroup) -> Int64 {
        group.files.filter { selectedURLs.contains($0.url) }.map(\.reclaimableSize).cappedSum
    }

    func isSelected(_ folder: DuplicateFolder) -> Bool {
        selectedFolders.contains(folder.url)
    }

    func canChange(_ folder: DuplicateFolder, in group: DuplicateFolderGroup) -> Bool {
        DuplicateScan.canChange(folder.url, among: group.folders.map(\.url), selected: selectedFolders)
    }

    /// Changes nothing that would leave the group with no copy.
    func setSelected(_ isSelected: Bool, _ folder: DuplicateFolder, in group: DuplicateFolderGroup) {
        guard canChange(folder, in: group) else { return }
        if isSelected {
            selectedFolders.insert(folder.url)
            selectedSizes.updateValue(reclaimableFolders[folder.url], forKey: folder.url)
        } else {
            unselect([folder.url])
        }
    }

    func selectedSize(in group: DuplicateFolderGroup) -> Int64 {
        group.folders.filter { selectedFolders.contains($0.url) }.map(\.reclaimableSize).cappedSum
    }

    /// Selects exactly `files` and `folders`.
    private func select(_ files: Set<URL>, folders: Set<URL>) {
        selectedURLs = files
        selectedFolders = folders
        selectedSizes = [:]
        for url in files { selectedSizes.updateValue(reclaimable[url], forKey: url) }
        for url in folders { selectedSizes.updateValue(reclaimableFolders[url], forKey: url) }
    }

    private func unselect(_ urls: some Collection<URL>) {
        selectedURLs.subtract(urls)
        selectedFolders.subtract(urls)
        for url in urls { selectedSizes.removeValue(forKey: url) }
    }
}

private extension DuplicateScan {
    func holds(_ row: DuplicateRow) -> Bool {
        switch row {
        case .folder(let id): folderGroups.contains { $0.id == id }
        case .file(let id): groups.contains { $0.id == id }
        }
    }
}

extension DuplicateLibrary: StoppableWork {
    var isRunning: Bool { isScanning }
}

extension DuplicateLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        guard selectedCount > 0 else { return [] }
        return [CarriedSelection.Part(
            page: Tool.duplicates.page(),
            title: String(localized: Tool.duplicates.title),
            source: Tool.duplicates.title.inEnglish,
            sourceKey: "tool",
            sizes: selectedSizes
        )]
    }

    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let scan else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let result = await DuplicateRemoval.trash(
            selectedURLs.filter { part.sizes.keys.contains($0) },
            folders: selectedFolders.filter { part.sizes.keys.contains($0) },
            from: scan,
            using: TrashService(exclusions: ExclusionsStore.shared.exclusions)
        )
        let trashed = Set(result.trashed.map(\.originalURL))
        // Reads the list again, since an exclusion can have narrowed it while the move ran.
        guard let latest = self.scan else { return result }
        let remaining = latest.removing(trashed)
        self.scan = remaining
        unselect(trashed)
        if let selection, !remaining.holds(selection) {
            self.selection = nil
        }
        return result
    }

    /// Nothing to bring up to date: the move took what it moved out of the list.
    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {}

    func deselect(_ part: CarriedSelection.Part) {
        unselect(part.sizes.keys)
    }
}
