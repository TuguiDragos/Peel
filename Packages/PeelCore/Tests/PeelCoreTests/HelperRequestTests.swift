import Foundation
import PeelPrivileged
import Testing

struct HelperRequestTests {
    private let someone = HelperRequest.Caller(user: 501, homeDirectory: "/Users/someone")

    private func admit(
        version: Int = HelperIdentity.protocolVersion,
        items: Int = 0,
        paths: [String] = [],
        asked: inout Int
    ) -> Result<HelperRequest.Caller, HelperRefusal> {
        HelperRequest.admit(version: version, items: items, paths: paths) {
            asked += 1
            return someone
        }
    }

    @Test func refusesAnotherVersionBeforeAskingWhoIsCalling() {
        var asked = 0
        #expect(throws: HelperRefusal.outOfDate) {
            try admit(version: HelperIdentity.protocolVersion - 1, asked: &asked).get()
        }
        #expect(asked == 0)
    }

    @Test func refusesTooManyItemsBeforeAskingWhoIsCalling() {
        var asked = 0
        #expect(throws: HelperRefusal.tooManyItems) {
            try admit(items: HelperRequest.maximumItems + 1, asked: &asked).get()
        }
        #expect(asked == 0)
        #expect((try? admit(items: HelperRequest.maximumItems, asked: &asked).get()) != nil)
    }

    @Test func refusesAPathLongerThanAnyRealOneBeforeAskingWhoIsCalling() {
        var asked = 0
        let longest = "/" + String(repeating: "a", count: HelperRequest.maximumPathLength - 1)
        #expect(throws: HelperRefusal.pathTooLong) { try admit(paths: ["/tmp", longest + "a"], asked: &asked).get() }
        #expect(asked == 0)
        #expect((try? admit(paths: [longest], asked: &asked).get()) != nil)
    }

    @Test func refusesAnAccountThatIsNotAllowed() {
        #expect(throws: HelperRefusal.notAllowed) {
            try HelperRequest.admit(version: HelperIdentity.protocolVersion) { nil }.get()
        }
    }

    @Test func answersWithTheCallerOfASoundRequest() throws {
        var asked = 0
        let caller = try admit(items: 3, paths: ["/Library/Caches/org.example.app"], asked: &asked).get()
        #expect(caller.user == 501)
        #expect(asked == 1)
    }
}
