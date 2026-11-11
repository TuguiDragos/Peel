import Foundation
@testable import Peel
import Testing

struct HidesFromDockNoteTests {
    @Test func saysWhereToOpenPeelWhenMacOSHidesItsMenuBarItem() {
        let note = GeneralSettingsView.hidesFromDockNote.key

        #expect(note.contains("menu bar is full"), "\(note)")
        #expect(note.contains("Finder or Spotlight"), "\(note)")
    }
}
