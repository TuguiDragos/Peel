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

    var folders: [URL] = [] {
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
    /// counts below, so summing the selection doesn't walk the whole scan on every change.
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
    var selectedURLs: Set<URL> = []
    var selectedFolders: Set<URL> = []
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
            folders = finder.defaultFolders
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

    var selectedReclaimableSize: Int64 {
        selectedURLs.reduce(0) { $0 + (reclaimable[$1] ?? 0) }
            + selectedFolders.reduce(0) { $0 + (reclaimableFolders[$1] ?? 0) }
    }

    private func readScan() {
        guard let scan else {
            reclaimable = [:]
            reclaimableFolders = [:]
            copyCount = 0
            groupCount = 0
            return
        }
        reclaimable = Dictionary(scan.groups.flatMap(\.files).map { ($0.url, $0.reclaimableSize) }) { first, _ in first }
        reclaimableFolders = Dictionary(scan.folderGroups.flatMap(\.folders).map { ($0.url, $0.reclaimableSize) }) { first, _ in first }
        copyCount = scan.groups.reduce(0) { $0 + $1.files.count } + scan.folderGroups.reduce(0) { $0 + $1.folders.count }
        groupCount = scan.groups.count + scan.folderGroups.count
    }

    /// Adds the folders Peel can scan and returns the others.
    func add(_ urls: [URL]) -> [URL] {
        for url in urls where finder.canScan(url) && !folders.contains(url) {
            folders.append(url)
        }
        return urls.filter { !finder.canScan($0) }
    }

    /// Starts a new scan. The previous one is canceled but not waited for, since a read stuck on a network
    /// share would hold back every later scan. Whatever it returns is dropped by its `generation`.
    func startScan() {
        scanTask?.cancel()
        generation += 1
        let current = generation
        scanTask = Task { await runScan(current) }
    }

    func stop() {
        scanTask?.cancel()
    }

    func clearResults() {
        scan = nil
        selection = nil
        selectedURLs = []
        selectedFolders = []
    }

    func removeSelected() async -> TrashResult {
        guard let scan else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let result = await DuplicateRemoval.trash(
            selectedURLs,
            folders: selectedFolders,
            from: scan,
            using: TrashService(exclusions: ExclusionsStore.shared.exclusions)
        )
        let trashed = Set(result.trashed.map(\.originalURL))
        // Reads the list again, since an exclusion can have narrowed it while the move ran.
        guard let latest = self.scan else { return result }
        let remaining = latest.removing(trashed)
        self.scan = remaining
        selectedURLs.subtract(trashed)
        selectedFolders.subtract(trashed)
        if let selection, !remaining.holds(selection) {
            self.selection = nil
        }
        return result
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
        selectedURLs = remaining.keepingOneOfEach(selectedURLs)
        selectedFolders = remaining.keepingOneOfEachFolder(selectedFolders)
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

        let (updates, continuation) = AsyncStream.makeStream(of: DuplicateScanProgress.self, bufferingPolicy: .bufferingNewest(1))
        let progressUpdates = Task {
            for await update in updates {
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
            selectedURLs = result.suggestedSelection
            selectedFolders = result.suggestedFolderSelection
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

    func setSelected(_ isSelected: Bool, _ file: DuplicateFile) {
        if isSelected {
            selectedURLs.insert(file.url)
        } else {
            selectedURLs.remove(file.url)
        }
    }

    func isSelected(_ folder: DuplicateFolder) -> Bool {
        selectedFolders.contains(folder.url)
    }

    func setSelected(_ isSelected: Bool, _ folder: DuplicateFolder) {
        if isSelected {
            selectedFolders.insert(folder.url)
        } else {
            selectedFolders.remove(folder.url)
        }
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
