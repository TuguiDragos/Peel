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

    @Test(.permissionsHold) func countsWhatItsPermissionsKeepThisAccountFromReading() async throws {
        let directory = try TemporaryDirectory()
        let closedFolder = try directory.directory("Closed")
        let notSearchable = try directory.directory("NotSearchable")
        let closedFile = try directory.file("closed.txt")
        let open = try directory.directory("Open")
        let openFile = try directory.file("open.txt")
        try directory.setPermissions(0o000, of: "Closed")
        try directory.setPermissions(0o400, of: "NotSearchable")
        try directory.setPermissions(0o000, of: "closed.txt")
        defer {
            try? directory.setPermissions(0o755, of: "Closed")
            try? directory.setPermissions(0o755, of: "NotSearchable")
        }

        #expect(await FileAccess.closedByPermissions(among: [closedFolder, notSearchable, closedFile]) == 3)
        #expect(await FileAccess.closedByPermissions(among: [closedFolder, open, openFile]) == 1)
        #expect(await FileAccess.closedByPermissions(among: [open, directory.url.appending(path: "gone")]) == 0)
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
