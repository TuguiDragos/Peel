import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct HomebrewTextTests {
    private let folder = URL(filePath: "/opt/example-homebrew", directoryHint: .isDirectory)

    @Test func theNotesAreShortAndSayWhatTheCodeDoes() {
        #expect(HomebrewList.aboutHomebrew.key == "Homebrew installs command-line tools as formulae and apps as casks. Peel runs Homebrew commands here and shows what they report. Forget is done by Peel itself: it moves the Homebrew receipt of a cask to the Trash.")
        #expect(HomebrewList.updateNote.key == "Gets the newest Homebrew and its list of packages, so run it before looking for updates. It upgrades nothing, though Homebrew may rename a package, reinstall pkgconf, or delete an old copy of its core taps.")
        #expect(HomebrewList.healthNote.key == "Asks Homebrew to check itself and report anything out of place, such as a broken link. It changes nothing, and it cannot see the PATH your Terminal uses.")
        #expect(HomebrewList.alreadyGoneNote.key == "Homebrew still lists these casks, but their apps are no longer where Homebrew put them, or macOS has no receipt left for their packages. Forgetting a cask moves its Homebrew receipt to the Trash, so Homebrew stops listing it, and History can put it back.")
        #expect(HomebrewList.retiredNote.key == "Homebrew deprecates a package before it stops offering it, then disables it: no new installs and no more upgrades. What is installed stays until you uninstall it.")
        #expect(HomebrewList.needsDefinitionsNote.key == "Asking Homebrew would download its list of packages again, which Peel does not start on its own.")
        #expect(HomebrewList.unreadSettingsNote("~/.config/homebrew/brew.env").key == "Peel runs Homebrew without your shell settings, so Homebrew reads ~/.homebrew/brew.env and not %@. Put what it should follow from Peel, such as a proxy, in ~/.homebrew/brew.env.")
        #expect(HomebrewVulnerabilitySections.howHomebrewChecked.key == "Homebrew checked this formula against OSV.dev, an open list of known vulnerabilities, leaving out those its own patches fix. “Fixed by its developers, version unknown” means OSV.dev names a fix but no version that carries it.")
        #expect(HomebrewDetailView.appGoneNote.key == "Its app is no longer where Homebrew put it, so Homebrew cannot upgrade it. Forget Cask moves its Homebrew receipt to the Trash, so Homebrew stops listing it, and History can put it back.")
        #expect(HomebrewDetailView.packagesGoneNote.key == "Its packages were uninstalled, or their receipts forgotten. If nothing of it is left, Forget Cask moves its Homebrew receipt to the Trash, and History can put it back.")
        #expect(HomebrewDetailView.stoppedMidUpgradeNote.key == "Its app is still in a Homebrew folder. Reinstalling the cask in Terminal puts it back.")
        #expect(HomebrewProgressView.stopNote.key == "A package being installed may be left half installed and need installing again. An app may stay in a Homebrew folder until you reinstall its cask.")
    }

    @Test func aFolderHomebrewCannotChangeIsInTheTitleAndTheStepEndsInTheCommand() {
        let root = HomebrewLibrary.CantChange.of(.init(folder: folder, owner: .root), isAdministrator: true)
        let asked = HomebrewLibrary.CantChange.of(.init(folder: folder, owner: .root), isAdministrator: false)
        let mine = HomebrewLibrary.CantChange.of(.init(folder: folder, owner: .thisAccount), isAdministrator: true)

        #expect(root.noteTitle.key == "Homebrew cannot change %@")
        #expect(root.detail.key == "%@ belongs to root, and Homebrew does not run as root.")
        #expect(root.step?.key == "Give it back to this account by running this in Terminal: %@")
        #expect(asked.detail.key == root.detail.key)
        #expect(asked.step?.key == "An administrator runs this in Terminal, or you run it after `su` and the short name of an administrator: %@")
        #expect(mine.noteTitle.key == "Homebrew cannot change %@")
        #expect(mine.detail.key == "%@ belongs to this account but cannot be written to.")
        #expect(mine.step?.key == "Let this account write to it by running this in Terminal: %@")
        #expect(root.command?.hasPrefix("sudo chown -R ") == true)
        #expect(mine.command?.hasPrefix("chmod u+w ") == true)
    }

    @Test func anotherAccountsHomebrewSaysWhoseItIs() {
        let named = HomebrewLibrary.CantChange.of(.init(folder: folder, owner: .another("Ana")), isAdministrator: true)
        let unnamed = HomebrewLibrary.CantChange.of(.init(folder: folder, owner: .another(nil)), isAdministrator: true)

        #expect(named.noteTitle.key == "Homebrew belongs to another account")
        #expect(named.detail.key == "Homebrew on this Mac belongs to %@, so only that account can update or change it.")
        #expect(unnamed.detail.key == "Only that account can update or change it.")
        #expect(named.step == nil && named.command == nil && unnamed.step == nil)
    }

    @Test func aStoppedUpgradeOffersTerminalBesideItsCommand() {
        let command = "brew reinstall --cask example"
        let actions = HomebrewDetailView.stoppedUpgradeActions(reinstalling: command)
        #expect(actions == [.copyReinstallCommand(command), .openTerminal])
    }
}
