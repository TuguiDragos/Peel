import Foundation
@testable import Peel
import PeelCore
import Testing

struct AppPageTextTests {
    @Test func theNotesOfAnAppsPageAreShort() {
        #expect(AppDetailView.recommendedNote.key == "Everything selected here goes to the Trash together. History can put it back while it is in the Trash.")
        #expect(AppDetailView.reviewNote.key == "Peel is less sure about these, another app uses them too, or a row says why Peel held it back. Nothing here is selected for you.")
        #expect(AppDetailView.removesItselfNote.key == "Remove Peel, in Settings > General, also removes its helper and login item, which a move from here would leave behind.")
        #expect(AppDetailView.webAppNote("Safari").key == "Moving it to the Trash takes away only this shortcut, and the app stays in %@. To remove the app itself, uninstall it in %@.")
        #expect(AppPageHeader.homebrewNeedsTerminal.key == "Homebrew needs an administrator password for this, and only Terminal can ask for it. Copy the command and run it in Terminal.")
        #expect(PrivacyResetRow.beforeTheMoveNote.key == "macOS keeps what an app was allowed to access, such as the camera, after the app is gone. Peel clears it just before the app goes to the Trash, so the app asks again if you install it later. Only when the app itself goes and no other copy stays.")
        #expect(PackageReceiptSection.note.key == "macOS keeps a receipt of the files a package installed. The ones outside the app are listed only to show them, since other software may rely on them. Forgetting the receipt, from the More menu, moves it to the Trash and leaves the files in place.")
        #expect(DefaultAppsSection.linksNote.key == "These links open with this app now. Once it is gone, they open with the app Peel shows; to choose another, use System Settings or that app.")
    }

    @Test func theDockRowSaysWhetherHistoryBringsTheIconBack() {
        #expect(DockTileOption.note(for: .moved).key.hasSuffix("Put back from History, the app gets its icon back."))
        #expect(DockTileOption.note(for: .alreadyInTheTrash).key.hasSuffix("so History does not bring its icon back."))
        #expect(DockTileOption.note(for: .both).key.hasSuffix("unless it was already in the Trash."))
    }

    @Test func theUpdateBadgeSaysWhyInFewerWords() {
        #expect(UpdateStatusBadge.reason(.namesNoFeed, name: "Example", brew: "brew").key == "%@ does not say where it updates from in a way Peel can read. Look for an update inside the app. Peel does not ask Apple about every app, since that would send Apple a list of what you have.")
        #expect(UpdateStatusBadge.reason(.notInTheAppStore, name: "Example", brew: "brew").key == "The App Store gives Peel no version of %@ to compare, as for an app it no longer sells or does not sell in your region. The App Store app knows when there is an update.")
    }

    @Test func theResetSheetIsShort() {
        #expect(ResetSheet.changeOfMindNote.key == "The old settings were saved before they were cleared. Put them back from here, or later from Settings > General > Saved Settings. History cannot put the old files back once the app writes new ones.")
        #expect(ResetSheet.privacyNote("Example").key == "Peel clears what %@ was allowed to access, such as the camera or the microphone, so it asks you again. History cannot bring that back.")
        #expect(AppReset.Group.settings.explanation.key == "The app writes these again the next time it opens. A license key or an account it remembered here may go too.")
    }
}
