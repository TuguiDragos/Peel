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
            return .success(someone)
        }
    }

    @Test func refusesAnotherVersionBeforeAskingWhoIsCalling() {
        var asked = 0
        for version in [HelperIdentity.protocolVersion - 1, HelperIdentity.protocolVersion + 1] {
            #expect(throws: HelperRefusal.outOfDate) {
                try admit(version: version, asked: &asked).get()
            }
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
            try HelperRequest.admit(version: HelperIdentity.protocolVersion) { .failure(.notAllowed) }.get()
        }
    }

    @Test func servesAnAdministratorWithoutAskingForAnApproval() throws {
        var asked = 0
        let caller = try HelperRequest.caller(
            user: 501, approval: Data(), isAdministrator: { _ in true },
            isApproved: { _ in
                asked += 1
                return false
            },
            homeDirectory: { _ in "/Users/someone" }
        ).get()

        #expect(caller.user == 501)
        #expect(asked == 0)
    }

    @Test func servesAnotherAccountOnlyWithAnAdministratorsApproval() throws {
        let approval = Data(repeating: 7, count: 32)
        func caller(approved: Bool) -> Result<HelperRequest.Caller, HelperRefusal> {
            HelperRequest.caller(
                user: 502, approval: approval, isAdministrator: { _ in false },
                isApproved: { $0 == approval && approved }, homeDirectory: { _ in "/Users/standard" }
            )
        }

        #expect(try caller(approved: true).get().homeDirectory == "/Users/standard")
        #expect(throws: HelperRefusal.notAuthorized) { try caller(approved: false).get() }
    }

    @Test func refusesAConnectionWithNoAccountOrNoHome() {
        #expect(throws: HelperRefusal.notAllowed) {
            try HelperRequest.caller(
                user: nil, approval: Data(), isAdministrator: { _ in true }, isApproved: { _ in true },
                homeDirectory: { _ in "/Users/someone" }
            ).get()
        }
        #expect(throws: HelperRefusal.notAllowed) {
            try HelperRequest.caller(
                user: 501, approval: Data(), isAdministrator: { _ in true }, isApproved: { _ in true },
                homeDirectory: { _ in nil }
            ).get()
        }
    }

    @Test func answersWithTheCallerOfASoundRequest() throws {
        var asked = 0
        let caller = try admit(items: 3, paths: ["/Library/Caches/org.example.app"], asked: &asked).get()
        #expect(caller.user == 501)
        #expect(asked == 1)
    }
}
