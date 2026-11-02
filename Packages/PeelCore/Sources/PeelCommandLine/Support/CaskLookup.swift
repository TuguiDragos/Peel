import Foundation
import PeelCore

enum CaskLookup {
    /// The casks Homebrew knows and the installer receipts, with how Homebrew failed when it did. A failure is
    /// kept apart from an empty list, which would wrongly say that no cask installed the app or has an update.
    struct Answer {
        var casks: [HomebrewPackage] = []
        /// Identifiers of the installer receipts on the Mac, used by the cask evidence and by the uninstall.
        var receipts: Set<String> = []
        var failure: Homebrew.CommandFailure?

        var note: String? {
            failure.map {
                ["Homebrew didn't answer, so what only its casks know is missing.", $0.output].compactMap(\.self)
                    .joined(separator: "\n")
            }
        }
    }

    /// Returns the casks and installer receipts that are evidence for `apps`: the casks Homebrew installed, and those
    /// its catalog lists for the rest. Homebrew is asked about casks only when it has a local copy of its definitions:
    /// otherwise it would download them, and looking up an app's leftovers or updates is no reason to go online.
    static func evidence(for apps: [InstalledApp]) async -> Answer {
        let receipts = await PackageReceipts.identifiers()
        // Receipts are evidence on their own, so they are returned even when Homebrew isn't asked.
        guard await Homebrew.hasLocalDefinitions() else { return Answer(receipts: receipts) }
        async let installed = Homebrew.installedPackages()
        let known = await CaskEvidence.knownCasks(for: apps, receipts: receipts)
        do {
            return Answer(
                casks: CaskEvidence.combined(installed: try await installed, known: known),
                receipts: receipts
            )
        } catch {
            return Answer(
                casks: CaskEvidence.combined(installed: [], known: known),
                receipts: receipts,
                failure: why(error)
            )
        }
    }

    /// Returns how Homebrew failed. It takes `any Error` because a typed `throws(Homebrew.CommandFailure)` arrives
    /// as `any Error` through `async let`.
    private static func why(_ error: any Error) -> Homebrew.CommandFailure {
        error as? Homebrew.CommandFailure ?? Homebrew.CommandFailure(output: error.localizedDescription)
    }
}
