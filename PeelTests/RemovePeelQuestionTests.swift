import Foundation
@testable import Peel
import Testing

struct RemovePeelQuestionTests {
    /// The helper serves every account, so the question says it goes whenever it is registered.
    @Test func theQuestionSaysTheHelperAndTheLoginItemGoOnlyWhileThereAreSome() throws {
        let both = try #require(SelfUninstall.whatGoesFirst(helperIsRegistered: true, opensAtLogin: true))
        let helper = try #require(SelfUninstall.whatGoesFirst(helperIsRegistered: true, opensAtLogin: false))
        let login = try #require(SelfUninstall.whatGoesFirst(helperIsRegistered: false, opensAtLogin: true))

        #expect(Set([both, helper, login]).count == 3)
        #expect(SelfUninstall.whatGoesFirst(helperIsRegistered: false, opensAtLogin: false) == nil)
    }
}
