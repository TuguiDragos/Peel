import Foundation
import PeelCore

enum CaskLookup {
    /// The casks Homebrew knows and the installer receipts, with Homebrew's message when it failed. A failure is
    /// kept apart from an empty list, which would wrongly say that no cask installed the app or has an update.
    struct Answer {
        var casks: [HomebrewPackage] = []
        /// Identifiers of the installer receipts on the Mac, used by the cask evidence and by the uninstall.
        var receipts: Set<String> = []
        var failure: String?

        var note: String? {
            failure.map { "Homebrew didn't answer, so what only its casks know is missing.\n\($0)" }
        }
    }

    /// Returns the casks and installer receipts that are evidence for `app`. Homebrew is asked about casks only
    /// when it has a local copy of its definitions: otherwise it would download them, and looking up an app's
    /// leftovers is no reason to go online.
    static func evidence(for app: InstalledApp) async -> Answer {
        let receipts = await PackageReceipts.identifiers()
        // Receipts are evidence on their own, so they are returned even when Homebrew isn't asked.
        guard await Homebrew.hasLocalDefinitions() else { return Answer(receipts: receipts) }
        async let installed = Homebrew.installedPackages()
        let known = await CaskEvidence.knownCasks(for: [app], receipts: receipts)
        do {
            return Answer(
                casks: CaskEvidence.combined(installed: try await installed, known: known, receipts: receipts),
                receipts: receipts
            )
        } catch {
            return Answer(
                casks: CaskEvidence.combined(installed: [], known: known, receipts: receipts),
                receipts: receipts,
                failure: why(error)
            )
        }
    }

    /// Returns the casks Homebrew installed, for the update check. A cask Homebrew only has a definition for says
    /// nothing about which version is installed.
    static func installed() async -> Answer {
        guard await Homebrew.hasLocalDefinitions() else { return Answer() }
        do {
            return Answer(casks: try await Homebrew.installedPackages())
        } catch {
            return Answer(failure: why(error))
        }
    }

    /// Returns what Homebrew printed when it failed, or else the error's description. It takes `any Error`
    /// because a typed `throws(Homebrew.CommandFailure)` arrives as `any Error` through `async let`.
    private static func why(_ error: any Error) -> String {
        (error as? Homebrew.CommandFailure)?.output ?? error.localizedDescription
    }
}
