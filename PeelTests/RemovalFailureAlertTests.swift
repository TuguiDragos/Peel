import Foundation
@testable import Peel
@testable import PeelCore
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
        let paragraphs = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        #expect(paragraphs.count == 4, "\(paragraphs)")
        #expect(paragraphs.filter { $0.contains("Example 30") }.isEmpty)
        let details = RemovalFailureAlert.details(for: outcome).components(separatedBy: "\n\n")
        #expect(details.filter { $0.contains("Example 30") }.count == 3)
    }

    @Test func saysEachReasonOnceWithTheItemsUnderIt() {
        let paths = (1...1_001).map { "/Users/someone/Library/Caches/org.example.item\($0)" }
        let outcome = RemovalOutcome()
        outcome.report(TrashResult(failures: paths.map { TrashFailure(url: URL(filePath: $0), reason: .notPermitted) }))
        let reason = TrashFailure.Reason.notPermitted.explanation

        let paragraphs = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        #expect(paragraphs.count == 2, "\(paragraphs)")
        #expect(paragraphs.first?.components(separatedBy: "\n").count == 1 + RemovalFailureAlert.mostListed)
        #expect(paragraphs.first?.hasPrefix(reason + "\n") == true)
        #expect(RemovalFailureAlert.message(for: outcome).components(separatedBy: reason).count == 2)
        #expect(RemovalFailureAlert.details(for: outcome).components(separatedBy: reason).count == 2)
        #expect(RemovalFailureAlert.details(for: outcome).contains("org.example.item1001"))
    }

    @Test func aReasonThatComesLateIsStillSaidAboveItsItems() {
        let outcome = RemovalOutcome()
        let failures = (1...10).map { TrashFailure(url: URL(filePath: "/Users/someone/a\($0)"), reason: .locked) }
            + [TrashFailure(url: URL(filePath: "/Users/someone/b1"), reason: .notPermitted)]
        outcome.report(TrashResult(failures: failures))

        let paragraphs = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        #expect(paragraphs.count == 3, "\(paragraphs)")
        let locked = TrashFailure.Reason.locked.explanation(for: 3)
        #expect(paragraphs[0] == ([locked] + (1...3).map { "/Users/someone/a\($0)" }).joined(separator: "\n"))
        #expect(paragraphs[1] == "\(TrashFailure.Reason.notPermitted.explanation)\n/Users/someone/b1")
    }

    @Test func aReasonAboveSeveralItemsIsWrittenForSeveral() {
        let paths = (1...3).map { "/Users/someone/a\($0)" }
        let outcome = RemovalOutcome()
        outcome.report(TrashResult(failures: paths.map { TrashFailure(url: URL(filePath: $0), reason: .locked) }))
        let forSeveral = String(localized: "They are locked. In Finder, choose File > Get Info for each and deselect Locked, then try again.")

        #expect(RemovalFailureAlert.message(for: outcome) == ([forSeveral] + paths).joined(separator: "\n"))
        #expect(RemovalFailureAlert.details(for: outcome) == ([forSeveral] + paths).joined(separator: "\n"))
    }

    @Test func aReasonAboveOneItemReadsAsItDoesForOne() {
        let one = RemovalOutcome()
        one.report(TrashResult(failures: [TrashFailure(url: URL(filePath: "/Users/someone/a1"), reason: .locked)]))
        #expect(RemovalFailureAlert.message(for: one) == TrashFailure.Reason.locked.explanation + "\n/Users/someone/a1")

        // Four reasons share the four items an alert lists, so each stands above one, though it has two.
        let reasons: [TrashFailure.Reason] = [.locked, .needsHelper, .changedSinceScan, .attachedDiskImage]
        let shared = RemovalOutcome()
        shared.report(TrashResult(failures: (1...2).flatMap { round in
            reasons.indices.map { TrashFailure(url: URL(filePath: "/Users/someone/b\($0)-\(round)"), reason: reasons[$0]) }
        }))
        let paragraphs = RemovalFailureAlert.message(for: shared).components(separatedBy: "\n\n")
        #expect(Array(paragraphs.prefix(4)) == reasons.indices.map { reasons[$0].explanation + "\n/Users/someone/b\($0)-1" })
        #expect(paragraphs.count == 5, "\(paragraphs)")
    }

    @Test func everyListUnderAReasonWritesItForSeveral() {
        let putBack = RemovalOutcome()
        putBack.reportPutBack(
            (1...2).map { .init(url: URL(filePath: "/Users/someone/p\($0)"), failure: .notInATrash) }, of: 2
        )
        let stayed = String(localized: "They are not in the Trash where Peel put them, so Peel leaves them where they are.")
        #expect(RemovalFailureAlert.message(for: putBack).contains(stayed + "\n/Users/someone/p1\n/Users/someone/p2"))

        let chosen = (1...2).map { (url: URL(filePath: "/Users/someone/f\($0)"), reason: ProjectArtifacts.Refusal.systemFolder) }
        #expect(ProjectList.reasons(chosen).hasPrefix(String(localized: "They are folders that macOS or every account uses, not folders of projects. Choose the folder your projects are in.")))

        let aside = (1...2).map {
            DuplicateScan.FolderSetAside(url: URL(filePath: "/Users/someone/d\($0)"), reason: .unreachable(.notAFolder))
        }
        #expect(DuplicateList.reasons(aside).hasPrefix(String(localized: "They are not folders.") + "\n"))

        let download = CloudRefusal(url: URL(filePath: "/Users/someone/c1"), reason: .keptDownloaded)
        #expect(download.explanation(for: 2) == String(localized: "Keep Downloaded is on for them in Finder, so iCloud would download them again."))
        #expect(download.explanation(for: 1) == download.explanation)
    }

    @Test func aSentenceOfTheHelperIsWrittenForSeveralAndAnyOtherStaysAsItCame() throws {
        let gone = TrashFailure.Reason.failed(FixedSentence.notThereAnymore.english)
        #expect(gone.explanation(for: 2) == String(localized: "They are not there anymore."))
        #expect(RestoreFailure.failed(FixedSentence.notInTrash.english).explanation(for: 2) == String(localized: "They are not in the Trash."))
        #expect(TrashFailure.Reason.failed("Input/output error").explanation(for: 2) == "Input/output error")

        let romanian = try #require(Bundle.main.url(forResource: "ro", withExtension: "lproj").flatMap(Bundle.init(url:)))
        let english = "They are locked. In Finder, choose File > Get Info for each and deselect Locked, then try again."
        let inRomanian = TrashFailure.Reason.locked.explanation(for: 2, in: romanian)
        #expect(inRomanian == String(localized: String.LocalizationValue(english), bundle: romanian))
        #expect(inRomanian != english)
    }

    @Test func aReasonThatNamesNoItemReadsTheSameAboveSeveral() {
        #expect(TrashFailure.Reason.notPermitted.explanation(for: 3) == TrashFailure.Reason.notPermitted.explanation)
        let unavailable = FixedSentence.helperUnavailable.english
        #expect(TrashFailure.Reason.failed(unavailable).explanation(for: 3) == FixedSentence.translated(unavailable))
        #expect(RestoreFailure.needsAppManagement.explanation(for: 3) == RestoreFailure.needsAppManagement.explanation)
        #expect(ProjectArtifacts.Refusal.tooBroad.explanation(for: 3) == ProjectArtifacts.Refusal.tooBroad.explanation)
        #expect(DuplicateFinder.Refusal.protected.explanation(for: 3) == DuplicateFinder.Refusal.protected.explanation)
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

    @Test func aPutBackWhoseJobDidNotStartAgainSaysWhatLaunchdAnswered() {
        let outcome = RemovalOutcome()
        outcome.reportPutBack([], of: 1, jobsNotStarted: [("org.example.server", "The configuration file is missing.")])

        #expect(!outcome.isEmpty)
        #expect(RemovalFailureAlert.message(for: outcome).contains("org.example.server"))
        #expect(RemovalFailureAlert.message(for: outcome).contains("The configuration file is missing."))
    }

    @Test func namesTheFirstFoldersAnAlertRefusesAndCountsTheOthers() {
        let most = RemovalFailureAlert.mostListed
        let paths = (1...30).map { "/Users/someone/Folder \($0)" }
        let shown = RemovalFailureAlert.firstItems(paths)
        #expect(shown.count == most + 1)
        #expect(Array(shown.prefix(most)) == Array(paths.prefix(most)))
        #expect(RemovalFailureAlert.firstItems(Array(paths.prefix(most))) == Array(paths.prefix(most)))

        let refused = paths.map { (url: URL(filePath: $0), reason: ProjectArtifacts.Refusal.neverSearched(.library)) }
        let reasons = ProjectList.reasons(refused).components(separatedBy: "\n\n")
        #expect(reasons.count == 2, "\(reasons.count)")
        #expect(reasons.first?.components(separatedBy: "\n").count == 1 + most)
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

    /// A line that runs what moved fails in every new Terminal window, so the alert says what to do about it.
    @Test func theShellLineSaysWhatToDoWithTheLines() {
        let outcome = RemovalOutcome()
        let file = URL(filePath: "/Users/someone/.zshrc")
        outcome.report(TrashResult(), shellReferences: [ShellReferences.Reference(file: file, line: 12)])
        let place = String(localized: "\(file.abbreviatedPath), line \(12)")

        #expect(RemovalFailureAlert.message(for: outcome).contains(String(
            localized: "Your shell startup files still name what moved, at \(place). If a new Terminal window shows an error, remove or change those lines: Peel reads these files and never changes them."
        )))
    }

    @Test func saysThatMacOSStartsAMovedAppsItemsFromTheTrashOnEveryMacOS() {
        let outcome = RemovalOutcome()
        outcome.report(TrashResult(), startingFromTheTrash: ["Example"])
        let line = String(
            localized: "macOS still starts the background items of \("Example") from the Trash each time you log in, until you empty the Trash."
        )

        #expect(RemovalFailureAlert.message(for: outcome).contains(line))
        #expect(RemovalFailureAlert.details(for: outcome).contains(line))
    }

    @Test func saysWhichIconsStayedInTheDockAndWhy() {
        let notRemembered = RemovalOutcome()
        notRemembered.report(TrashResult(), dockIcons: RemovalOutcome.DockIcons(apps: ["Example"], reason: .notRemembered))
        let notSaved = RemovalOutcome()
        notSaved.report(TrashResult(), dockIcons: RemovalOutcome.DockIcons(apps: ["Example"], reason: .notSaved))
        let couldNotSave = String(
            localized: "The Dock still shows \("Example"): Peel takes an icon out only once it has saved where to put it back, and it could not save that."
        )
        let notSavedLine = String(localized: "The Dock still shows \("Example"): macOS did not save the change to the Dock.")

        #expect(!notRemembered.isEmpty)
        #expect(RemovalFailureAlert.message(for: notRemembered).contains(couldNotSave))
        #expect(RemovalFailureAlert.details(for: notRemembered).contains(couldNotSave))
        #expect(RemovalFailureAlert.message(for: notSaved).contains(notSavedLine))
    }

    @Test func namesTheAppsMacOSDidntRecognizeInOneParagraph() {
        let apps = ["Lantern", "Proxyman", "Seabird", "Seawall Launcher", "Owl", "Wren"].enumerated().map { index, name in
            InstalledApp(
                url: URL(filePath: "/Applications/\(name).app"), bundleIdentifier: "org.example.app\(index)", name: name
            )
        }
        let four = RemovalOutcome()
        four.report(TrashResult(), privacy: apps.prefix(4).map { ($0, .notKnownToTheSystem) })
        let paragraphs = RemovalFailureAlert.message(for: four).components(separatedBy: "\n\n")
        #expect(paragraphs.count == 1, "\(paragraphs)")
        #expect(apps.prefix(4).allSatisfy { paragraphs[0].contains($0.name) })
        let six = RemovalOutcome()
        six.report(TrashResult(), privacy: apps.map { ($0, .notKnownToTheSystem) })
        let shown = RemovalFailureAlert.message(for: six)
        #expect(shown.components(separatedBy: "\n\n").count == 1 && !shown.contains("Owl") && !shown.contains("Wren"))
        #expect(RemovalFailureAlert.details(for: six).contains("Wren"))
        let one = RemovalOutcome()
        one.report(TrashResult(), privacy: [(apps[0], .notKnownToTheSystem)])
        #expect(RemovalFailureAlert.message(for: one).contains("Lantern"))
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
        let quit = paragraphs.filter { $0.contains("Example") }
        #expect(quit.count == 1, "\(quit)")
        #expect(quit.first?.contains("Example 4") == true && quit.first?.contains("Example 5") == false)
        let shell = paragraphs.first { $0.contains(".zshrc") } ?? ""
        #expect(shell.contains("40") && !shell.contains("50") && !shell.contains("60"), "\(shell)")
        let details = RemovalFailureAlert.details(for: outcome)
        #expect(details.contains("Example 6") && details.contains("60"))
        #expect(RemovalFailureAlert.offersDetails(for: outcome))
    }
}
