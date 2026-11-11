import Foundation
@testable import PeelCore
import Testing

struct OtherAccountsTests {
    @Test func aHomeOfAnotherAccountIsSeenAndSharedIsNobodys() throws {
        let directory = try TemporaryDirectory()
        let users = try directory.directory("Users")
        try FileManager.default.createDirectory(at: users.appending(path: "Shared"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: users.appending(path: ".localized"), withIntermediateDirectories: true)
        try Data().write(to: users.appending(path: "notes.txt"))

        #expect(!OtherAccounts.exist(in: users, besides: getuid() + 1), "Shared, a hidden name, and a file are no home")
        try FileManager.default.createDirectory(at: users.appending(path: "ana"), withIntermediateDirectories: true)
        #expect(OtherAccounts.exist(in: users, besides: getuid() + 1))
        #expect(!OtherAccounts.exist(in: users, besides: getuid()), "this account's own home")
        #expect(!OtherAccounts.exist(in: directory.url.appending(path: "nowhere")))
    }
}
