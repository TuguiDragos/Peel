import Darwin
import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

/// Moves into the Trash, and back out of it, never replace what is already at the new name. exFAT cannot refuse to
/// replace by itself: `RENAME_EXCL` answers `ENOTSUP` there for a free name and `EEXIST` for a taken one, and these
/// tests stand in for it.
struct TrashMoverTests {
    private func likeExFAT(_ item: OpenItem, _ name: String, _ directory: DirectoryHandle) -> Result<Void, POSIXError> {
        var info = stat()
        let isTaken = name.withCString { fstatat(directory.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) } == 0
        return .failure(POSIXError(isTaken ? .EEXIST : .ENOTSUP))
    }

    private func contents(of url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).sorted()
    }

    @Test func aFileMovesWhereTheDiskCannotRefuseToReplace() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("folder/notes.txt", contents: Data("mine".utf8))
        let trash = try directory.directory("Trash")
        let item = try OpenItem.at(file.path(percentEncoded: false)).get()

        let landed = try TrashMover.move(item, into: try DirectoryHandle.at(trash.path(percentEncoded: false)).get(), exclusively: likeExFAT).get()

        #expect(URL(filePath: landed).lastPathComponent == "notes.txt")
        #expect(try String(contentsOfFile: landed, encoding: .utf8) == "mine")
        #expect(!file.isThere)
        #expect(try contents(of: trash) == ["notes.txt"])
    }

    @Test func whatIsAlreadyThereIsNeverReplaced() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("folder/notes.txt", contents: Data("mine".utf8))
        let earlier = try directory.file("Trash/notes.txt", contents: Data("in the Trash already".utf8))
        let item = try OpenItem.at(file.path(percentEncoded: false)).get()

        let trash = try DirectoryHandle.at(earlier.deletingLastPathComponent().path(percentEncoded: false)).get()
        let landed = try TrashMover.move(item, into: trash, exclusively: likeExFAT).get()

        #expect(URL(filePath: landed).lastPathComponent == "notes 2.txt")
        #expect(try String(contentsOf: earlier, encoding: .utf8) == "in the Trash already")
        #expect(try String(contentsOfFile: landed, encoding: .utf8) == "mine")
    }

    @Test func aFolderMovesWithEverythingInIt() throws {
        let directory = try TemporaryDirectory()
        try directory.file("folder/Project/one.txt", contents: Data("1".utf8))
        try directory.file("folder/Project/deeper/two.txt", contents: Data("2".utf8))
        let trash = try directory.directory("Trash")
        let item = try OpenItem.at(directory.url.appending(path: "folder/Project").path(percentEncoded: false)).get()

        let landed = URL(filePath: try TrashMover.move(item, into: try DirectoryHandle.at(trash.path(percentEncoded: false)).get(), exclusively: likeExFAT).get())

        #expect(try String(contentsOf: landed.appending(path: "one.txt"), encoding: .utf8) == "1")
        #expect(try String(contentsOf: landed.appending(path: "deeper/two.txt"), encoding: .utf8) == "2")
        #expect(try contents(of: trash) == ["Project"])
    }

    /// A move that fails once the new name is taken for it gives the name back, so neither the Trash nor the place an
    /// item was being put back to is left holding an empty stand-in.
    @Test func aMoveThatFailsLeavesNothingBehind() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("locked/notes.txt")
        let folder = try directory.directory("Project/inside")
        let trash = try directory.directory("Trash")
        let item = try OpenItem.at(file.path(percentEncoded: false)).get()
        let folderItem = try OpenItem.at(folder.path(percentEncoded: false)).get()
        try directory.setPermissions(0o555, of: "locked")
        try directory.setPermissions(0o555, of: "Project")
        defer {
            try? directory.setPermissions(0o755, of: "locked")
            try? directory.setPermissions(0o755, of: "Project")
        }

        let bin = try DirectoryHandle.at(trash.path(percentEncoded: false)).get()
        #expect(throws: POSIXError.self) { try TrashMover.move(item, into: bin, exclusively: likeExFAT).get() }
        #expect(throws: POSIXError.self) { try TrashMover.move(folderItem, into: bin, exclusively: likeExFAT).get() }
        #expect(try contents(of: trash).isEmpty)
        #expect(file.isThere && folder.isThere)
    }

    @Test func putBackNeverReplacesWhatCameBackInTheMeantime() throws {
        let directory = try TemporaryDirectory()
        let trashed = try directory.file("Trash/notes.txt", contents: Data("from the Trash".utf8))
        let place = try directory.directory("folder")
        let item = try OpenItem.at(trashed.path(percentEncoded: false)).get()
        let folder = try DirectoryHandle.at(place.path(percentEncoded: false)).get()

        try TrashMover.rename(item, to: "notes.txt", in: folder, exclusively: likeExFAT).get()
        #expect(try String(contentsOf: place.appending(path: "notes.txt"), encoding: .utf8) == "from the Trash")

        let another = try directory.file("Trash/other.txt", contents: Data("another".utf8))
        let second = try OpenItem.at(another.path(percentEncoded: false)).get()
        #expect(throws: POSIXError(.EEXIST)) { try TrashMover.rename(second, to: "notes.txt", in: folder, exclusively: likeExFAT).get() }
        #expect(try String(contentsOf: place.appending(path: "notes.txt"), encoding: .utf8) == "from the Trash")
        #expect(another.isThere)
    }
}
