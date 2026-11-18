import Foundation
@testable import Peel
import Testing

struct IntelEmptyTests {
    private static let placesOnAppleSilicon = "Nothing Peel looked at needs Rosetta: the apps in the Applications folders and the folders you added in Settings, what they carry inside, the plug-ins, the drivers, the background items, the Java runtimes, and the tools in /usr/local, /opt/homebrew, /opt/local, ~/bin, and ~/.local/bin."
    private static let placesOnIntel = "Nothing Peel looked at is built for Intel only: the apps in the Applications folders and the folders you added in Settings, what they carry inside, the plug-ins, the drivers, the background items, the Java runtimes, and the tools in /usr/local, /opt/local, ~/bin, and ~/.local/bin."
    private static let settingsList = "The Intel-based Apps list in System Settings > General > About names the apps macOS 28 won’t run, including some outside the folders Peel looks in."

    @Test func theNoteHoldsThePlacesPeelLookedInAndTheListSystemSettingsKeeps() {
        let withTheList = IntelList.empty(onAppleSilicon: true, settingsListsIntelApps: true)
        #expect(withTheList.title.key == "Nothing Needs Rosetta")
        #expect(withTheList.note.map(\.key) == [Self.placesOnAppleSilicon, Self.settingsList])

        let withoutTheList = IntelList.empty(onAppleSilicon: true, settingsListsIntelApps: false)
        #expect(withoutTheList.title.key == "Nothing Needs Rosetta")
        #expect(withoutTheList.note.map(\.key) == [Self.placesOnAppleSilicon])

        let onIntel = IntelList.empty(onAppleSilicon: false, settingsListsIntelApps: false)
        #expect(onIntel.title.key == "Nothing Built for Intel Only")
        #expect(onIntel.note.map(\.key) == [Self.placesOnIntel])
    }
}
