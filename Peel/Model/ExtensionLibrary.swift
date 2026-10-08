import Foundation
import Observation
import PeelCore

@Observable
final class ExtensionLibrary {
    private(set) var extensions: [AppExtension]?
    /// The kinds macOS gave no answer about, which is not the same as there being none of them.
    private(set) var unanswered: Set<AppExtension.Kind> = []
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    var selection: AppExtension.ID?

    var selectedExtension: AppExtension? {
        extensions?.first { $0.id == selection }
    }

    func refresh() async {
        guard let scan = await scanRun.run({ await AppExtensions.scan(exclusions: ExclusionsStore.shared.exclusions) })
        else { return }
        let result = scan.extensions
        extensions = result
        unanswered = scan.unanswered
        if let selection, !result.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }
}

extension AppExtension.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .appExtension: "Part of an app"
        case .systemExtension: "Installed into macOS"
        }
    }

    var systemImage: String {
        switch self {
        case .appExtension: "puzzlepiece.extension"
        case .systemExtension: "gearshape.2"
        }
    }

    /// What the page says when macOS gave no answer about this kind.
    var unansweredNote: LocalizedStringResource {
        switch self {
        case .appExtension: "macOS didn’t say which app extensions are on this Mac, so none are listed here."
        case .systemExtension: "macOS didn’t say which system extensions are on this Mac, so none are listed here."
        }
    }
}

extension AppExtension.Election {
    var title: LocalizedStringResource {
        switch self {
        case .on: "Turned on"
        case .off: "Turned off"
        case .asItCame: "Default"
        case .superseded: "Replaced"
        case .waitingForApproval: "Waiting for approval"
        case .beingRemoved: "Being removed"
        case .changing: "Changing"
        case .unknown: LocalizedStringResource("Unknown (extension state)", defaultValue: "Unknown")
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .on: "Someone turned this on and macOS kept the choice."
        case .off: "Someone turned this off and macOS kept the choice."
        case .asItCame: "Nobody has decided about it, so macOS chooses."
        case .superseded: "Another copy of this extension is the one macOS runs."
        case .waitingForApproval: "macOS won’t run this until you allow it in System Settings."
        case .beingRemoved: "macOS is removing this. Some removals finish only when the Mac restarts."
        case .changing: "macOS is partway through changing this."
        case .unknown: "macOS doesn’t know this extension’s state, or reports one Peel doesn’t recognize."
        }
    }

    /// The symbol the list shows in the accent color beside a choice someone made, and beside waiting for approval,
    /// the only state the user can do something about.
    var mark: String? {
        switch self {
        case .on: "checkmark.circle"
        case .waitingForApproval: "exclamationmark.circle"
        default: nil
        }
    }
}
