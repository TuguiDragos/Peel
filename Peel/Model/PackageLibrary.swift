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
    /// When a receipt last changed as the last scan began, so a receipt written, forgotten, or put back elsewhere since
    /// is noticed: on an app's page, by an uninstall, from History, or by an installer.
    private var scannedChange: Date?

    var selectedReceipt: PackageReceipt? {
        receipts?.first { $0.id == selection }
    }

    /// Takes out of the selection what waits for the helper while the helper can't act: its checkbox is off then, and
    /// a move would only refuse it, so it would stay selected, and counted, for every move after.
    func follow(canUseHelper: Bool) {
        let kept = Self.selection(selectedURLs, in: receipts ?? [], canUseHelper: canUseHelper)
        if kept != selectedURLs { selectedURLs = kept }
    }

    static func selection(_ selected: Set<URL>, in receipts: [PackageReceipt], canUseHelper: Bool) -> Set<URL> {
        selected.subtracting(receipts.flatMap(\.items).filter { $0.isLocked(canUseHelper: canUseHelper) }.map(\.url))
    }

    func refresh() async {
        let change = PackageActions.receiptsChanged()
        guard
            let scan = await scanRun.run({ await PackageReceipts.list(exclusions: ExclusionsStore.shared.exclusions) })
        else { return }
        scannedChange = change
        let result = scan.receipts
        receipts = result
        couldNotAsk = scan.couldNotAsk
        selectedURLs.formIntersection(Set(result.flatMap(\.items).filter { !$0.isLeftAlone }.map(\.url)))
        if let selection, !result.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    /// Reads the receipts again when one changed since the last scan.
    func refreshIfReceiptsChanged() async {
        guard receipts != nil, !isScanning, !isWorking else { return }
        guard PackageActions.receiptsChanged() != scannedChange else { return }
        await refresh()
    }

    func removeSelectedItems(recording record: (TrashResult) async -> Void) async -> TrashResult {
        isWorking = true
        defer { isWorking = false }
        let items = selectedReceipt?.items.filter { selectedURLs.contains($0.url) } ?? []
        let privileged = Set(items.filter(\.requiresPrivileges).map(\.url))
        let result = await QuitGuard.shared.run {
            let result = await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(
                items.map(\.url),
                usingHelperFor: privileged,
                lettingTheirProgramsRun: Set(items.filter { $0.uninstallsItself != nil }.map(\.url))
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
