import Foundation
@testable import Peel
import Testing

@MainActor
struct SystemExtensionNoteTests {
    /// On macOS 27 as on 26, the note says that Peel leaves the app and its files, which Orphaned Files lists later.
    @Test func everyNoteOn27SaysWhatPeelLeaves() {
        for isOne in [true, false] {
            for deletes in [true, false] {
                let said = SystemExtensionNotice.saidOn27(
                    names: "Example Extension", app: "Example", isOne: isOne, systemSettingsDeletesThem: deletes
                ).map { String(localized: $0) }
                #expect(said.count == 2)
                #expect(said.last?.contains("Orphaned Files") == true)
            }
        }
    }
}
