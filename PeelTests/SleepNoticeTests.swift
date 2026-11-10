import Foundation
@testable import Peel
import Testing

struct SleepNoticeTests {
    /// The command comes with what it is for and where it runs, and an administrator hears that it asks a password.
    @Test func theCommandSaysWhatItIsForAndWhereItRuns() {
        let administrator = SleepNotice.howToUndo(needsAnAdministrator: false).key
        let standard = SleepNotice.howToUndo(needsAnAdministrator: true).key

        #expect(administrator.hasPrefix("To let it sleep again, run this command in Terminal."))
        #expect(administrator.contains("password") && !standard.contains("password"))
    }
}
