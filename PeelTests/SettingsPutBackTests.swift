import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct SettingsPutBackTests {
    /// A Put Back that left part of the copy says what went back and what stayed, never only its title.
    @Test func anIncompletePutBackSaysWhatDidNotGoBack() {
        let left = PreferenceBackup.Restored.saidAfterIncomplete(clearedSome: false)

        #expect(left.contains("The rest went back."))
        #expect(left != PreferenceBackup.Restored.saidAfterIncomplete(clearedSome: true))
    }
}
