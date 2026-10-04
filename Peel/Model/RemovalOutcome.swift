import Foundation
import Observation
import PeelCore

/// What a removal could not do, held by the app rather than by the page that asked. Removing an app closes its
/// page, and an alert owned by that page would close with it.
@Observable
final class RemovalOutcome {
    /// What came of one app's privacy reset.
    struct Privacy: Hashable {
        let app: String
        let result: PrivacyReset.Result
    }

    private(set) var failures: [TrashFailure] = []
    /// The privacy resets the removal ran that are worth telling the user about.
    private(set) var privacy: [Privacy] = []
    /// The apps to quit before what their tools kept can move.
    private(set) var appsToQuit: [String] = []
    private(set) var movedCount = 0

    var isEmpty: Bool { failures.isEmpty && privacy.isEmpty && appsToQuit.isEmpty }

    /// Keeps what the removal could not do, for the alert. `privacy` is every reset the removal ran, and
    /// `PrivacyReset.worthTelling` picks which of them to tell. A removal with nothing to tell changes nothing.
    func report(
        _ result: TrashResult,
        privacy resets: [(app: InstalledApp, result: PrivacyReset.Result)] = [],
        appsToQuit: [String] = []
    ) {
        let privacy = PrivacyReset.worthTelling(resets, after: result).map {
            Privacy(app: $0.app.name, result: $0.result)
        }
        guard !result.failures.isEmpty || !privacy.isEmpty || !appsToQuit.isEmpty else { return }
        failures = result.failures
        movedCount = result.trashed.count
        self.privacy = privacy
        self.appsToQuit = appsToQuit
    }

    func clear() {
        failures = []
        movedCount = 0
        privacy = []
        appsToQuit = []
    }
}
