import Foundation
import Observation
import PeelCore

/// What a removal could not do, or left for a restart to finish, held by the app rather than by the page that asked.
/// Removing an app closes its page, and an alert owned by that page would close with it.
@Observable
final class RemovalOutcome {
    /// What came of one app's privacy reset.
    struct Privacy: Hashable {
        let app: String
        let result: PrivacyReset.Result
    }

    struct PutBackFailure: Hashable {
        let url: URL
        let failure: RestoreFailure
    }

    private(set) var failures: [TrashFailure] = []
    /// The privacy resets the removal ran that are worth telling the user about.
    private(set) var privacy: [Privacy] = []
    /// The apps to quit before what their tools kept can move.
    private(set) var appsToQuit: [String] = []
    /// The apps that stayed while files of their own were selected, which stayed with them.
    private(set) var keptTheirFiles: [String] = []
    /// The audio drivers that moved, which macOS keeps running until the Mac restarts.
    private(set) var driversAwaitingARestart: [String] = []
    /// The apps that moved whose background items macOS still starts at login from the Trash (`TrashResult`).
    private(set) var appsStartingFromTheTrash: [String] = []
    /// How many of the items the removal left stay for an administrator, which Orphaned Files lists.
    private(set) var leftForAnAdministrator = 0
    /// The lines of the shell startup files that still name what moved, which the person edits.
    private(set) var shellReferences: [ShellReferences.Reference] = []
    /// True when History couldn't record the removal, so Put Back has nothing to go on for what moved.
    private(set) var historyCouldNotRecord = false
    /// What an Undo left in the Trash: Undo is asked from any page, so what came of it is told here.
    private(set) var putBackFailures: [PutBackFailure] = []
    private(set) var movedCount = 0

    var isEmpty: Bool {
        failures.isEmpty && privacy.isEmpty && appsToQuit.isEmpty && driversAwaitingARestart.isEmpty
            && appsStartingFromTheTrash.isEmpty && leftForAnAdministrator == 0 && shellReferences.isEmpty
            && !historyCouldNotRecord && putBackFailures.isEmpty
    }

    func noteHistoryCouldNotRecord() {
        historyCouldNotRecord = true
    }

    func reportPutBack(_ failures: [PutBackFailure]) {
        putBackFailures = failures
    }

    /// Keeps what the removal could not do, what a restart or an emptied Trash finishes, and what stays for an
    /// administrator, for the alert. `privacy` is every reset the removal ran, and `PrivacyReset.worthTelling` picks
    /// which of them to tell. A removal with nothing to tell changes nothing.
    func report(
        _ result: TrashResult,
        privacy resets: [(app: InstalledApp, result: PrivacyReset.Result)] = [],
        appsToQuit: [String] = [],
        keptTheirFiles: [String] = [],
        startingFromTheTrash: [String] = [],
        leftForAnAdministrator: Int = 0,
        shellReferences: [ShellReferences.Reference] = []
    ) {
        let privacy = PrivacyReset.worthTelling(resets, after: result).map {
            Privacy(app: $0.app.name, result: $0.result)
        }
        let drivers = AudioDrivers.awaitingARestart(after: result)
        guard
            !result.failures.isEmpty || !privacy.isEmpty || !appsToQuit.isEmpty || !drivers.isEmpty
                || !startingFromTheTrash.isEmpty || leftForAnAdministrator > 0 || !shellReferences.isEmpty
        else { return }
        failures = result.failures
        movedCount = result.trashed.count
        self.privacy = privacy
        self.appsToQuit = appsToQuit
        self.keptTheirFiles = keptTheirFiles
        driversAwaitingARestart = drivers
        self.leftForAnAdministrator = leftForAnAdministrator
        self.shellReferences = shellReferences
        // Two copies of an app share its name and its background items.
        var named: Set<String> = []
        appsStartingFromTheTrash = startingFromTheTrash.filter { named.insert($0).inserted }
    }

    func clear() {
        failures = []
        movedCount = 0
        privacy = []
        appsToQuit = []
        keptTheirFiles = []
        driversAwaitingARestart = []
        appsStartingFromTheTrash = []
        leftForAnAdministrator = 0
        shellReferences = []
        historyCouldNotRecord = false
        putBackFailures = []
    }
}
