import Foundation
@testable import PeelCore
import Testing

struct FileAccessTests {
    @Test func anItemInAFolderOfOnesOwnNeedsNoAdministrator() throws {
        let directory = try TemporaryDirectory()
        #expect(!FileAccess.requiresPrivilegesToRemove(try directory.file("Folder/file.txt")))
        #expect(!FileAccess.requiresPrivilegesToRemove(try directory.directory("Folder/Inner")))
    }

    @Test(.permissionsHold) func anItemInAFolderThatCannotBeWrittenNeedsAnAdministrator() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("Locked/file.txt")
        try directory.setPermissions(0o555, of: "Locked")
        defer { try? directory.setPermissions(0o755, of: "Locked") }

        #expect(FileAccess.requiresPrivilegesToRemove(file))
    }

    /// macOS answers `EPERM` both for an item its privacy protection keeps from this process, as it keeps another
    /// developer's app from a process without App Management, and for one that is locked. Only the first is a
    /// permission the person can give.
    @Test func tellsAPrivacyRefusalFromALock() throws {
        #expect(FileAccess.isProtectedByPrivacy(accessError: EPERM, isLocked: false))
        #expect(!FileAccess.isProtectedByPrivacy(accessError: EPERM, isLocked: true))
        #expect(!FileAccess.isProtectedByPrivacy(accessError: EACCES, isLocked: false))
        #expect(!FileAccess.isProtectedByPrivacy(accessError: nil, isLocked: false))

        let directory = try TemporaryDirectory()
        let locked = try directory.directory("Locked.app")
        #expect(chflags(locked.path(percentEncoded: false), UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(locked.path(percentEncoded: false), 0) }
        #expect(!FileAccess.isProtectedByPrivacy(locked))
        #expect(!FileAccess.isProtectedByPrivacy(try directory.directory("Plain.app")))
    }

    @Test func whatMacOSOwnsNeedsAnAdministrator() {
        #expect(FileAccess.requiresPrivilegesToRemove(URL(filePath: "/System/Applications/Calculator.app")))
    }
}
