import Foundation
import Observation
import PeelCore

@Observable
final class PackageLibrary {
    private(set) var receipts: [PackageReceipt]?
    /// macOS could not be asked what is installed, which is not the same as nothing being installed.
    private(set) var couldNotAsk = false
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isWorking = false
    var selection: PackageReceipt.ID?
    var selectedURLs: Set<URL> = []

    var selectedReceipt: PackageReceipt? {
        receipts?.first { $0.id == selection }
    }

    func refresh() async {
        guard
            let scan = await scanRun.run({ await PackageReceipts.list(exclusions: ExclusionsStore.shared.exclusions) })
        else { return }
        let result = scan.receipts
        receipts = result
        couldNotAsk = scan.couldNotAsk
        selectedURLs.formIntersection(Set(result.flatMap(\.items).filter { !$0.isLeftAlone }.map(\.url)))
        if let selection, !result.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func removeSelectedItems(recording record: (TrashResult) async -> Void) async -> TrashResult {
        isWorking = true
        defer { isWorking = false }
        let items = selectedReceipt?.items.filter { selectedURLs.contains($0.url) } ?? []
        let privileged = Set(items.filter(\.requiresPrivileges).map(\.url))
        let result = await QuitGuard.shared.run {
            let result = await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(
                items.map(\.url),
                usingHelperFor: privileged
            )
            // Written down before the rescan, which can take a while: History is the way back for what just moved.
            await record(result)
            return result
        }
        await refresh()
        return result
    }

    func forget(_ receipt: PackageReceipt, recording record: (TrashResult) async -> Void) async -> TrashResult {
        isWorking = true
        defer { isWorking = false }
        let result = await QuitGuard.shared.run {
            let result = await PackageActions.forget(receipt, exclusions: ExclusionsStore.shared.exclusions)
            await record(result)
            return result
        }
        await refresh()
        return result
    }
}
