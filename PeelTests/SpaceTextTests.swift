import Foundation
@testable import Peel
import PeelCore
import Testing

struct SpaceTextTests {
    private func about(_ area: String) -> String? {
        SpaceItem.words(for: area)?.detail.key
    }

    @Test func eachAreaSaysWhatItIsInAFewSentences() {
        #expect(about("system-logs") == "Logs that apps and services wrote for every account, and the crash reports macOS keeps. Only the logs are offered, never their folders, and what a service wrote in the last 15 minutes stays.")
        #expect(about("homebrew-data") == "What Homebrew formulae keep in its var folder, such as the data of a database. Uninstalling with Homebrew leaves it, and a folder no installed formula names is marked.")
        #expect(about("user-caches") == "What apps cached in a folder macOS gives your account, which Finder hides. What an open app uses stays, and the folders of developer tools are left to the Developer page.")
        #expect(about("system-caches") == "What apps cached for every account on this Mac. What an open app uses, or a service wrote in the last 15 minutes, stays.")
        #expect(about("container-caches") == "What sandboxed apps, such as those from the App Store, cached in their containers. What an open app uses stays, and the caches of Apple apps are listed but never selected.")
        #expect(about("mail-downloads") == "Copies of the attachments you opened in Mail. One you edited or saved may be the only copy, so they are listed and never selected.")
        #expect(about("homebrew-logs") == "Logs that the services Homebrew runs, such as a database, write in its folder. Only the logs are offered, never their folders.")
        #expect(about("battlenet-cache") == "What the Battle.net app caches for every account. Blizzard says removing it does not affect your games. It belongs to every account, so it is never selected.")
        #expect(about("logs") == "Logs that apps wrote in your Library and in their containers, and the crash reports macOS keeps for your account. The crash reports are offered one by one, and the folder they sit in always stays.")
        #expect(about("caches") == "What apps cached in your Library, each folder moved whole. The folders of developer tools are left to the Developer page.")
    }

    @Test func theNotesUnderTheListAreShortWithWhyInTheirCircledI() {
        #expect(SpaceDetailView.quitToInclude(["Safari"]).key == "Quit %@ to include its folders")
        #expect(SpaceDetailView.quitToInclude(["Safari", "Xcode"]).key == "Quit %@ to include their folders")
        #expect(SpaceDetailView.openAppsNote.key == "Peel leaves out the folders an open app is writing to. It can tell only by the name or identifier of the app.")
        #expect(SpaceDetailView.leftAlone(3).key == "Peel leaves ^[%lld folder](inflect: true) here alone")
        let work = "An app keeps work there that exists nowhere else, such as the local history of an editor."
        let protected = "Peel protects what is there, such as what iCloud keeps to stay in sync, a wallet, the documents of an app, or a library."
        #expect(SpaceDetailView.whyLeftAlone(keepingWork: 1, protected: 0).map(\.key) == [work])
        #expect(SpaceDetailView.whyLeftAlone(keepingWork: 0, protected: 2).map(\.key) == [protected])
        #expect(SpaceDetailView.whyLeftAlone(keepingWork: 1, protected: 2).map(\.key) == [work, protected])
    }

    /// `tmutil deletelocalsnapshots` deletes only Time Machine's snapshots, while the list can hold macOS's too.
    @Test func theSnapshotCommandIsSaidToDeleteOnlyTimeMachineSnapshots() {
        #expect(SpaceList.deleteNote("tmutil deletelocalsnapshots /").key == "Peel does not remove snapshots, since a deleted one cannot be put back. `%@` deletes Time Machine snapshots, if you are sure.")
    }
}
