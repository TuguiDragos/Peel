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

    @Test func whatMacOSOwnsNeedsAnAdministrator() {
        #expect(FileAccess.requiresPrivilegesToRemove(URL(filePath: "/System/Applications/Calculator.app")))
    }
}
