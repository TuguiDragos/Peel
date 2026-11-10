import Foundation
@testable import Peel
import Testing

struct AgentSavedAlertTests {
    /// An agent of the Background session lives in the user domain, which a logout doesn't end.
    @Test func aJobLaunchdDidNotStopRunsUntilItsDomainEnds() {
        #expect(BackgroundItemList.notStoppedWords(endsAtLogout: true).key.contains("until you log out"))
        #expect(BackgroundItemList.notStoppedWords(endsAtLogout: false).key.contains("until the Mac restarts"))
    }
}
