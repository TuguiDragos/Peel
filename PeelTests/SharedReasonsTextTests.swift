import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct SharedReasonsTextTests {
    @Test func aRowSaysWhyWithoutTheSameTailEachTime() {
        #expect(HoldBack.holdsVPNConnections.explanation.key == "Not selected: it holds VPN connections, with their keys and certificates, that may exist only on this Mac.")
        #expect(HoldBack.holdsPasswordsOrCodes.explanation.key == "Not selected: it holds passwords or sign-in codes that may exist only on this Mac.")
        #expect(HoldBack.holdsLocalMail.explanation.key == "Not selected: it may hold mail kept only on this Mac, such as a local or POP account.")
        #expect(HoldBack.holdsMessageHistory.explanation.key == "Not selected: it holds message history that may exist only on this Mac.")
        #expect(HoldBack.holdsTorrents.explanation.key == "Not selected: it holds your list of torrents and how far each one got.")
        #expect(HoldBack.holdsWorkMadeWithTheApp.explanation.key == "Not selected: it holds what you made with the app, such as saved games or databases, which may exist only on this Mac.")
        #expect(HoldBack.holdsSimulators.explanation.key == "Not selected: it holds the simulators of the app, with their apps and data.")
        #expect(HoldBack.holdsVirtualMachines.explanation.key == "Not selected: it holds virtual machines or Windows bottles, with everything in them.")
        #expect(HoldBack.holdsWhatAToolKeeps.explanation.key == "Not selected: a developer tool may still use what it keeps here, such as packages or model weights.")
        #expect(HoldBack.holdsTerraformState.explanation.key == "Not selected: it holds the state Terraform or OpenTofu keeps, the only copy with a local backend.")
        #expect(HoldBack.couldNotLookInside.explanation.key == "Left alone: macOS kept Peel from looking inside, so Peel cannot tell whether it holds something it protects, such as a wallet. Full Disk Access may let Peel see.")
        #expect(HoldBack.tooManyToLookThrough.explanation.key == "Left alone: a folder inside holds too many items for Peel to look through, so Peel cannot tell whether it holds something it protects, such as a wallet.")
        #expect(HoldBack.couldNotBeRead.explanation.key == "Not selected: macOS kept Peel from reading inside. Full Disk Access may let Peel see.")
        #expect(HoldBack.closedByPermissions.explanation.key == "Not selected: its own permissions keep your account out, which Full Disk Access does not change.")
    }

    @Test func aSystemExtensionRowSaysWhoRemovesItTheSameOn26And27() {
        #expect(HoldBack.systemExtension.explanation.key == "Left alone: macOS removes this system extension only when its app goes to the Trash in Finder. If the app is gone, install it again, use the feature that needs the extension and allow it when macOS asks, then move the app to the Trash in Finder and restart.")
        #expect(HoldBack.deletableSystemExtension.explanation.key == "Left alone: only macOS removes this system extension. Delete it in System Settings > General > Login Items & Extensions > By Category > Network Extensions.")
        #expect(HoldBack.systemExtensionOfAnAppInside.explanation.key == "Left alone: macOS installed this for an app inside another app, and moving that app does not remove it. While it is turned off, macOS does not run it.")
        let finder = { (carried: CarriedSystemExtensions) in
            RemovedElsewhere.byFinder(systemExtensions: carried).explanation.key
        }
        #expect(finder(.notKnown) == "Left alone: Peel cannot see which system extensions the app carries, and macOS removes those only when the app goes to the Trash in Finder.")
        #expect(finder(CarriedSystemExtensions(names: ["Example"])) == "Left alone: only macOS removes %@, when the app goes to the Trash in Finder.")
        #expect(finder(CarriedSystemExtensions(names: ["Example"], systemSettingsDeletesThem: true)) == "Left alone: only macOS removes %@, when the app goes to the Trash in Finder. If it stays, delete it in System Settings > General > Login Items & Extensions > By Category > Network Extensions.")
        #expect(finder(CarriedSystemExtensions(names: ["Example", "Other"], systemSettingsDeletesThem: true)) == "Left alone: only macOS removes %@, when the app goes to the Trash in Finder. If they stay, delete them in System Settings > General > Login Items & Extensions > By Category > Network Extensions.")
    }

    @Test func theAlertsSayWhatToDoInFewerWords() {
        let one = ["Example"].formatted(.list(type: .and))
        let two = ["Example", "Other"].formatted(.list(type: .and))
        #expect(TrashFailure.Reason.heldByAnotherAccount(by: ["Example"]).explanation(in: nil) == String(localized: "It is in use by \(one), which runs as another account or as the system, so neither you nor Peel can quit it. Stop it in Background Items, or with the uninstaller of its app, then try again."))
        #expect(TrashFailure.Reason.heldByAnotherAccount(by: ["Example", "Other"]).explanation(in: nil) == String(localized: "It is in use by \(two), which run as another account or as the system, so neither you nor Peel can quit them. Stop them in Background Items, or with the uninstaller of their app, then try again."))
        #expect(RestoreFailure.emptyFolderInItsPlace.explanation == String(localized: "An empty folder was made here after this moved, often by the app that uses it. Quit that app, move the empty folder to the Trash, then put this back."))
    }

    @Test func whyHistoryCannotBeWrittenEndsWithWhatPeelDoesMeanwhile() {
        let folder = URL(filePath: "/Users/someone/Library/Application Support/Peel", directoryHint: .isDirectory)
        let file = folder.appending(path: "removals.journal")
        let problems: [HistoryWriteProblem] = [
            .folderNotWritable(folder), .diskFull(free: 1, needed: 2), .noRoomLeft(folder), .freeSpaceNotKnown(folder),
            .journalUnreadable(file), .journalNotWritable(file), .lockClosed(file), .aLink(file),
        ]
        for problem in problems {
            let said = problem.explanation()
            #expect(!said.contains("so that everything it moves can be put back"), "\(said)")
            #expect(!said.contains("\u{2019}"), "\(said)")
        }
        #expect(HistoryWriteProblem.aLink(file).explanation() == String(localized: "\(file.abbreviatedPath) is a link, and Peel keeps History only in files of its own. Peel removes nothing until the link is gone."))
    }

    @Test func aTeamChangeSaysWhatPeelSawFirstInFewerWords() {
        let named = TeamRegistry.Change(bundleIdentifier: "org.example.app", previous: "AAAAAAAAAA", current: "BBBBBBBBBB")
        #expect(named.explanation(named: "Example Inc") == String(localized: "It was first seen signed by team \("AAAAAAAAAA"), and is signed by \("Example Inc"), team \("BBBBBBBBBB"), now. A maker can change teams, as after a sale, but a copy someone rebuilt looks the same. If you did not expect this, get the app again from its maker."))
        #expect(named.explanation(named: nil) == String(localized: "It was first seen signed by team \("AAAAAAAAAA"), and is signed by team \("BBBBBBBBBB") now. A maker can change teams, as after a sale, but a copy someone rebuilt looks the same. If you did not expect this, get the app again from its maker."))
    }

    @Test func anUninstallerSaysItIsOneOnItsRow() throws {
        let page = try #require(URL(string: "https://example.com/uninstall"))
        let itself = MakersUninstaller(maker: "Example", step: .notOnTheMac, instructions: page, removes: "Example Suite")
        let another = MakersUninstaller(maker: "Example", step: .notOnTheMac, instructions: page, removes: nil)
        #expect(RemovedElsewhere.byItsMaker(itself).explanation.key == "Left alone: this app is an uninstaller.")
        #expect(RemovedElsewhere.byItsMaker(another).explanation.key == "Left alone: use its own uninstaller.")
    }
}
