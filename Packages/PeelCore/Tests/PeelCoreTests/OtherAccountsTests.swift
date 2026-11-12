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

    @Test func theNoteAboutOtherAccountsFollowsWhatAFilterKeeps() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        let group = { (name: String, folder: String) in
            OrphanGroup(identifier: name, items: [
                OrphanItem(
                    url: URL(filePath: "\(folder)/\(name)"), kind: .caches, size: 1, modificationDate: nil,
                    requiresPrivileges: false
                ),
            ])
        }
        let own = group("org.example.own", "/Users/me/Library/Caches")
        let shared = group("org.example.shared", "/Library/Caches")
        let scan = OrphanScan(groups: [own, shared], unreadableLocations: [], foldersOfThisAccountAlone: [home])

        #expect(scan.otherAccountsMayOwn)
        #expect(scan.leavingOut(given: [:], installedApps: [], tools: .notKnown).otherAccountsMayOwn)
        #expect(scan.without(own.id).otherAccountsMayOwn)
        #expect(!scan.without(shared.id).otherAccountsMayOwn, "nothing listed is outside the home anymore")
        #expect(!OrphanScan(groups: [own, shared], unreadableLocations: []).otherAccountsMayOwn, "no other account")

        let apart = OrphanScan(
            groups: [own], unreadableLocations: [],
            forAnAdministrator: [AdministratorItem(item: shared.items[0], apps: ["Gone"])],
            foldersOfThisAccountAlone: [home]
        )
        #expect(apart.otherAccountsMayOwn, "what is listed for an administrator counts too")
    }
}
