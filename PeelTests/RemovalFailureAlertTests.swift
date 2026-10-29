import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct RemovalFailureAlertTests {
    @Test func listsTheFirstAppsThatStayedAndCountsTheOthers() {
        let apps = (1...30).map { index in
            InstalledApp(
                url: URL(filePath: "/Applications/Example \(index).app"),
                bundleIdentifier: "org.example.app\(index)", name: "Example \(index)"
            )
        }
        let outcome = RemovalOutcome()
        outcome.report(
            TrashResult(failures: apps.map { TrashFailure(url: $0.url, reason: .locked) }),
            privacy: apps.map { ($0, .reset) },
            keptTheirFiles: apps.map(\.name)
        )
        let most = RemovalFailureAlert.mostListed
        let paragraphs = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        #expect(paragraphs.count == 3 * (most + 1), "\(paragraphs.count)")
        #expect(paragraphs.filter { $0.contains("Example 30") }.isEmpty)
        let details = RemovalFailureAlert.details(for: outcome).components(separatedBy: "\n\n")
        #expect(details.filter { $0.contains("Example 30") }.count == 3)
    }

    @Test func namesTheAppThatSyncsWhatStaysAndItsMarker() {
        let marker = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".stfolder")
        let syncthing = SyncKeeper.app(.syncthing, marker: marker)

        #expect(String(localized: GuardRefusal.inTheCloud(syncthing).explanation) == String(localized: "Peel won’t move this: it is in a folder \("Syncthing") syncs to your other devices (its marker is \("~/.stfolder")), and moving it to the Trash would also remove it from them."))
        #expect(String(localized: GuardRefusal.inTheCloud(.cloud).explanation) == String(localized: "Peel won’t move this: it syncs to your other devices through iCloud or another app, and moving it to the Trash would also remove it from them."))
        #expect(String(localized: HoldBack.inTheCloud.explanation(keptInStepBy: syncthing)) == String(localized: "Left alone: this is in a folder \("Syncthing") syncs to your other devices (its marker is \("~/.stfolder")), and moving it to the Trash would also remove it from them."))
        #expect(
            String(localized: HoldBack.notMeasured.explanation(keptInStepBy: syncthing))
                == String(localized: HoldBack.notMeasured.explanation)
        )
        #expect(ProjectArtifacts.Refusal.inTheCloud(syncthing).explanation == String(localized: "It is in a folder \("Syncthing") syncs to your other devices (its marker is \("~/.stfolder")), which Peel leaves to that app."))
    }

    @Test func anUndoThatMacOSRefusedNamesAppManagementAndNotTheMove() {
        let outcome = RemovalOutcome()
        outcome.reportPutBack([
            .init(url: URL(filePath: "/Applications/Example.app"), failure: .needsAppManagement),
        ], of: 1)

        let message = RemovalFailureAlert.message(for: outcome)

        #expect(message.contains(RestoreFailure.needsAppManagement.explanation))
        #expect(!message.contains("to the Trash."), "\(message)")
    }

    @Test func namesTheFirstFoldersAnAlertRefusesAndCountsTheOthers() {
        let most = RemovalFailureAlert.mostListed
        let paths = (1...30).map { "/Users/someone/Folder \($0)" }
        let shown = RemovalFailureAlert.firstItems(paths)
        #expect(shown.count == most + 1)
        #expect(Array(shown.prefix(most)) == Array(paths.prefix(most)))
        #expect(RemovalFailureAlert.firstItems(Array(paths.prefix(most))) == Array(paths.prefix(most)))

        let refused = paths.map { (url: URL(filePath: $0), reason: ProjectArtifacts.Refusal.neverSearched) }
        let reasons = ProjectList.reasons(refused).components(separatedBy: "\n\n")
        #expect(reasons.count == most + 1, "\(reasons.count)")
        #expect(!reasons.contains { $0.contains("Folder 30") })
    }

    @Test func copiesTheShellLineTheAlertShows() {
        let outcome = RemovalOutcome()
        outcome.report(
            TrashResult(failures: [TrashFailure(url: URL(filePath: "/Applications/Example.app"), reason: .locked)]),
            shellReferences: [ShellReferences.Reference(file: URL(filePath: "/Users/someone/.zshrc"), line: 12)]
        )
        let shown = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        let line = shown.first { $0.contains("/Users/someone/.zshrc") }
        #expect(line != nil)
        #expect(RemovalFailureAlert.details(for: outcome).components(separatedBy: "\n\n").contains(line ?? ""))
    }

    @Test func offersTheDetailsWhereTheAlertNamesOnlyTheFirstApps() {
        let apps = (1...6).map { index in
            InstalledApp(
                url: URL(filePath: "/Applications/Example \(index).app"),
                bundleIdentifier: "org.example.app\(index)", name: "Example \(index)"
            )
        }
        let many = RemovalOutcome()
        many.report(TrashResult(), privacy: apps.map { ($0, .notKnownToTheSystem) })
        #expect(RemovalFailureAlert.offersDetails(for: many))
        let few = RemovalOutcome()
        few.report(TrashResult(), privacy: apps.prefix(2).map { ($0, .notKnownToTheSystem) })
        #expect(!RemovalFailureAlert.offersDetails(for: few))
    }

    @Test func namesTheFirstAppsToQuitAndShellLinesAndCountsTheOthers() {
        let outcome = RemovalOutcome()
        outcome.report(
            TrashResult(),
            appsToQuit: (1...6).map { "Example \($0)" },
            shellReferences: (1...6).map {
                ShellReferences.Reference(file: URL(filePath: "/Users/someone/.zshrc"), line: $0 * 10)
            }
        )
        let paragraphs = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        #expect(paragraphs.filter { $0.contains("Example") }.count == RemovalFailureAlert.mostListed)
        let shell = paragraphs.first { $0.contains(".zshrc") } ?? ""
        #expect(shell.contains("40") && !shell.contains("50") && !shell.contains("60"), "\(shell)")
        let details = RemovalFailureAlert.details(for: outcome)
        #expect(details.contains("Example 6") && details.contains("60"))
        #expect(RemovalFailureAlert.offersDetails(for: outcome))
    }
}
