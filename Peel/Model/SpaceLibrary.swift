import Foundation
import Observation
import PeelCore

@Observable
final class SpaceLibrary: RowSelection {
    private(set) var report: SpaceReport?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    var selection: SpaceItem.ID?
    /// What is selected inside the chosen item's folders.
    var selectedURLs: Set<URL> = []
    var isRemoving = false

    var selectedItem: SpaceItem? {
        report?.items.first { $0.id == selection }
    }

    func refresh() async {
        guard let result = await scanRun.run({ await SpaceInventory.scan() }) else { return }
        report = result
        if let selection, !result.items.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }
}

extension SpaceItem.Category {
    var title: LocalizedStringResource {
        switch self {
        case .development: "Development"
        case .virtualMachines: "Virtual Machines"
        case .media: "Media and Backups"
        case .cloud: "Cloud Storage"
        case .library: "Your Library"
        }
    }

    var systemImage: String {
        switch self {
        case .development: "hammer"
        case .virtualMachines: "server.rack"
        case .media: "play.rectangle"
        case .cloud: "cloud"
        case .library: "books.vertical"
        }
    }
}
