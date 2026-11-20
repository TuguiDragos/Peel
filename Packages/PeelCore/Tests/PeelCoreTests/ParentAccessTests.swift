import Darwin
import Foundation
@testable import PeelCore
import Testing

struct ParentAccessTests {
    /// `man 7 sticky`: in a sticky folder, an item can be removed only by its owner, the folder's owner, or root.
    @Test func aStickyFolderKeepsOnlyWhatIsNeitherTheUsersNorInTheUsersFolder() {
        #expect(!ParentAccess.stickyFolderKeeps(itemOwnedBy: 501, folderOwnedBy: 0, from: 501))
        #expect(!ParentAccess.stickyFolderKeeps(itemOwnedBy: 502, folderOwnedBy: 501, from: 501))
        #expect(!ParentAccess.stickyFolderKeeps(itemOwnedBy: 502, folderOwnedBy: 503, from: 0))
        #expect(ParentAccess.stickyFolderKeeps(itemOwnedBy: 502, folderOwnedBy: 0, from: 501))
    }

    /// The same rule on the disk: the user can remove anything from a sticky folder the user owns.
    @Test func aStickyFolderOfTheUsersOwnNeedsNoAdministrator() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Shared")
        let item = try directory.file("Shared/item.txt")
        #expect(chmod(folder.path(percentEncoded: false), 0o1755) == 0)

        #expect(!ParentAccess(folder).requiresPrivileges(toRemove: item))
    }

    @Test(.permissionsHold) func aFolderLockedInFinderIsLockedForAnAdministratorToo() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("home/Library/Caches/org.example.locked")
        try directory.file("home/Library/Caches/org.example.locked/cache.db")
        let path = folder.path(percentEncoded: false)
        #expect(chflags(path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(path, 0) }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let trash = try directory.directory("Trash")
        let service = TrashService(environment: environment) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        #expect(!ParentAccess(folder.deletingLastPathComponent()).requiresPrivileges(toRemove: folder))
        #expect(!FileAccess.requiresPrivilegesToRemove(folder))
        let result = await service.trash([folder], usingHelperFor: [])
        #expect(result.failures.map(\.reason) == [.locked])
        #expect(!folder.isMissing)
    }
}
