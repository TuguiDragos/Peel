import Foundation
import Observation
import PeelCore

@Observable
final class CloudLibrary {
    private(set) var files: [CloudFile]?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isFreeing = false
    private(set) var refusals: [CloudRefusal] = []
    /// `wasCutShort`: there is more than the list shows. `couldNotRead`: iCloud Drive couldn't be read at all.
    private(set) var wasCutShort = false
    private(set) var couldNotRead = false
    var selectedURLs: Set<URL> = []

    var totalSize: Int64 {
        files?.reduce(0) { $0 + $1.size } ?? 0
    }

    var selectedSize: Int64 {
        files?.filter { selectedURLs.contains($0.url) }.reduce(0) { $0 + $1.size } ?? 0
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
        let refused = await CloudStorage.free(chosen)
        let kept = Set(refused.map(\.url))
        await refresh()
        refusals = refused
        return chosen.filter { !kept.contains($0.url) }.reduce(0) { $0 + $1.size }
    }
}
