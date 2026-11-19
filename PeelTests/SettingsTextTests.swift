import Foundation
@testable import Peel
import PeelCore
import Testing

struct SettingsTextTests {
    @Test func theNotesAreShortAndTrue() {
        #expect(GeneralSettingsView.checkForUpdatesNote.key == "Peel asks the feed of each app, the App Store, or Homebrew for the latest version, and never installs anything itself. With this off, Peel looks for its own updates only when you choose Check for Updates.")
        #expect(GeneralSettingsView.preferUpdatesNote.key == "Automatic asks Homebrew first about an app it installed, then the feed of the app or the App Store. Any other choice asks the source you prefer first. The catalog of Homebrew answers last, for an app Homebrew did not install.")
        #expect(GeneralSettingsView.hidesFromDockNote.key == "While Peel shows in the menu bar, its icon leaves the Dock when its last window closes, and comes back when you open Peel from the menu bar, Finder, or Spotlight. If the menu bar is full, macOS may hide Peel there.")
        #expect(GeneralSettingsView.diskAlmostFullNote.key == "While Peel runs, it sends a notification when less than a tenth of the disk with your home folder is free. Clicking it opens Space.")
        #expect(GeneralSettingsView.removePeelNote.key == "Peel removes its helper and login item, moves itself, its own files, and its folder in Application Support to the Trash, clears its settings, and quits. That folder holds History and your exclusions. What you set in Tweaks and on the Terminal page stays.")
        #expect(GeneralSettingsView.removePeelQuestion.key == "Peel, its own files, and its folder in Application Support go to the Trash, and its settings are cleared. That folder holds History, your exclusions, and your saved settings. What you set in Tweaks and on the Terminal page stays as it is.")
        #expect(GeneralSettingsView.removedWithHomebrew.key == "Homebrew installed this copy of Peel, so remove it with Homebrew.")
        #expect(GeneralSettingsView.removedWithHomebrewNote.key.hasPrefix("Homebrew deletes the app instead of moving it to the Trash"))
        #expect(AppFoldersSection.note.key == "Peel looks for apps in the Applications folders and in the folders on this list. Apps on a disk that is not connected still count as installed, so their files are not listed as orphaned.")
        #expect(HomebrewSection.note.key == "Peel runs the `brew` in /opt/homebrew or /usr/local. If your Homebrew is elsewhere, choose its `brew`: Peel and `peel` then run that one, and its upgrades and uninstalls go to Terminal.")
        #expect(HelperSettingsView.about.key == "A small tool with administrator rights that moves items to the Trash and back, controls background items, and forgets installer receipts. It takes no other orders.")
        #expect(ExclusionsSettingsView.unreadableNote.key == "Peel removes and puts back nothing until it can read them or you start over. Adding or removing an entry starts over, keeping the old file beside the new one.")
    }

    @Test func eachStateIsShortWithTheRestInItsNote() {
        #expect(GeneralSettingsView.trashClosed.key == "Peel cannot read your Trash")
        #expect(GeneralSettingsView.trashClosedNote.key == "The permissions of the folder keep this account out, so Peel is not watching it.")
        #expect(GeneralSettingsView.trashNotWatched.key == "Not watching the Trash right now")
        #expect(GeneralSettingsView.trashNotWatchedNote.key == "Peel tries again each time you come back to it.")
        #expect(GeneralSettingsView.notificationsAreOff.key == "Notifications are off for Peel")
        #expect(GeneralSettingsView.cannotOfferLeftovers.key == "So Peel cannot offer to remove what an app left behind.")
        #expect(GeneralSettingsView.cannotWarnDiskFull.key == "So Peel cannot warn you when the disk is almost full.")
        #expect(GeneralSettingsView.waitingForHomebrew.key == "Waiting for Homebrew…")
        #expect(GeneralSettingsView.homebrewSaidNothing.key == "Homebrew did not say what is installed")
        #expect(GeneralSettingsView.homebrewMustUpdate.key == "Homebrew needs to update first")
        #expect(GeneralSettingsView.homebrewNotRun.key == "Peel does not run this Homebrew")
        #expect(GeneralSettingsView.removedWithHomebrewToo.key == "A copy Homebrew installed is removed with Homebrew.")
        #expect(GeneralSettingsView.moveToApplicationsFirst.key == "Move Peel to the Applications folder first")
        #expect(GeneralSettingsView.linkBreaksIfPeelMoves("/Users/me/Downloads/Peel.app").key == "The link points at Peel where it is now, %@, so it breaks if Peel moves.")
        #expect(HelperSettingsView.notAnswering.key == "The Peel helper is not answering")
        #expect(HelperSettingsView.notAnsweringNote.key == "Repair installs the Peel helper that matches this version of Peel.")
        #expect(SavedSettingsSection.unreadable.key == "Peel cannot read the saved copies")
        #expect(SavedSettingsSection.unreadableNote.key == "None can be listed or put back until it can.")
        #expect(AppFoldersSection.unreadable.key == "Peel cannot read its list of app folders")
        #expect(AppFoldersSection.unreadableNote.key == "Orphaned Files lists nothing until it can. Starting over keeps the old list beside the new one.")
        #expect(ExclusionsSettingsView.ownersUnreadableTitle.key == "Peel cannot read this list")
        #expect(ExclusionsSettingsView.ownersUnreadableNote.key == "Orphaned Files lists these files again until it can. Starting over keeps the old list beside the new one.")
    }

    @Test func aRefusedBrewSaysWhyInAFewWords() {
        #expect(HomebrewChoice.Refusal.ownedByAnotherAccount(owner: "sam").reason.key == "Another account owns this `brew`")
        #expect(HomebrewChoice.Refusal.ownedByAnotherAccount(owner: "sam").more?.key == "The account %@ owns it and could change what Peel runs, so Peel runs only a `brew` that your account or the system owns.")
        #expect(HomebrewChoice.Refusal.ownedByAnotherAccount(owner: nil).more?.key == "That account could change what Peel runs, so Peel runs only a `brew` that your account or the system owns.")
        #expect(HomebrewChoice.Refusal.unreadable.reason.key == "Peel cannot read which `brew` you chose")
        #expect(HomebrewChoice.Refusal.unreadable.more?.key == "It runs none until you choose it again or use the usual places.")
        #expect(HomebrewChoice.Refusal.notAProgram.more == nil)
    }

    @Test func removePeelsRefusalsSayTheStep() {
        #expect(SelfUninstall.explanation(of: .readOnlyCopy) == "Peel runs from a copy it cannot move. Quit Peel, move it to the Applications folder, open it there, and choose Remove Peel again.")
        #expect(SelfUninstall.explanation(of: .leftToFinder) == "Peel will not move itself from here: this account is not allowed to move it. Dragging Peel to the Trash in Finder leaves its helper, its login item, and its files behind.")
        #expect(SelfUninstall.explanation(of: .needsAnAdministrator).hasSuffix("Dragging Peel to the Trash in Finder leaves its helper, its login item, and its files behind."))
        #expect(SelfUninstall.explanation(of: .needsItsOwner("sam")).hasSuffix("Dragging Peel to the Trash in Finder leaves its helper, its login item, and its files behind."))
    }
}
