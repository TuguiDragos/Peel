import Darwin
import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

/// Moves into the Trash, and back out of it, never replace what is already at the new name. exFAT cannot refuse to
/// replace by itself: `RENAME_EXCL` answers `ENOTSUP` there for a free name and `EEXIST` for a taken one. So these
/// tests run on an exFAT disk made for them.
struct TrashMoverTests {
    private func contents(of url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).filter { !$0.hasPrefix(".") }.sorted()
    }

    private func write(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func folder(_ url: URL) throws -> DirectoryHandle {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return try DirectoryHandle.at(url.path(percentEncoded: false)).get()
    }

    @Test func aFileMovesWhereTheDiskCannotRefuseToReplace() throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "ExFAT", mountedAt: directory.url.appending(path: "Stick", directoryHint: .isDirectory))
        let file = disk.url.appending(path: "folder/notes.txt")
        try write("mine", at: file)
        let trash = disk.url.appending(path: "Trash", directoryHint: .isDirectory)

        let landed = try TrashMover.move(try OpenItem.at(file.path(percentEncoded: false)).get(), into: try folder(trash)).get()

        #expect(URL(filePath: landed).lastPathComponent == "notes.txt")
        #expect(try String(contentsOfFile: landed, encoding: .utf8) == "mine")
        #expect(!file.isThere)
        #expect(try contents(of: trash) == ["notes.txt"])
    }

    @Test func whatIsAlreadyThereIsNeverReplaced() throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "ExFAT", mountedAt: directory.url.appending(path: "Stick", directoryHint: .isDirectory))
        let file = disk.url.appending(path: "folder/notes.txt")
        let earlier = disk.url.appending(path: "Trash/notes.txt")
        try write("mine", at: file)
        try write("in the Trash already", at: earlier)

        let item = try OpenItem.at(file.path(percentEncoded: false)).get()
        let landed = try TrashMover.move(item, into: try folder(earlier.deletingLastPathComponent())).get()

        #expect(URL(filePath: landed).lastPathComponent == "notes 2.txt")
        #expect(try String(contentsOf: earlier, encoding: .utf8) == "in the Trash already")
        #expect(try String(contentsOfFile: landed, encoding: .utf8) == "mine")
    }

    @Test func aFolderMovesWithEverythingInIt() throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "ExFAT", mountedAt: directory.url.appending(path: "Stick", directoryHint: .isDirectory))
        try write("1", at: disk.url.appending(path: "folder/Project/one.txt"))
        try write("2", at: disk.url.appending(path: "folder/Project/deeper/two.txt"))
        let trash = disk.url.appending(path: "Trash", directoryHint: .isDirectory)

        let item = try OpenItem.at(disk.url.appending(path: "folder/Project").path(percentEncoded: false)).get()
        let landed = URL(filePath: try TrashMover.move(item, into: try folder(trash)).get())

        #expect(try String(contentsOf: landed.appending(path: "one.txt"), encoding: .utf8) == "1")
        #expect(try String(contentsOf: landed.appending(path: "deeper/two.txt"), encoding: .utf8) == "2")
        #expect(try contents(of: trash) == ["Project"])
    }

    @Test func putBackNeverReplacesWhatCameBackInTheMeantime() throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "ExFAT", mountedAt: directory.url.appending(path: "Stick", directoryHint: .isDirectory))
        let trashed = disk.url.appending(path: "Trash/notes.txt")
        let another = disk.url.appending(path: "Trash/other.txt")
        try write("from the Trash", at: trashed)
        try write("another", at: another)
        let place = disk.url.appending(path: "folder", directoryHint: .isDirectory)
        let destination = try folder(place)

        try TrashMover.rename(try OpenItem.at(trashed.path(percentEncoded: false)).get(), to: "notes.txt", in: destination).get()
        #expect(try String(contentsOf: place.appending(path: "notes.txt"), encoding: .utf8) == "from the Trash")

        let second = try OpenItem.at(another.path(percentEncoded: false)).get()
        #expect(throws: POSIXError(.EEXIST)) { try TrashMover.rename(second, to: "notes.txt", in: destination).get() }
        #expect(try String(contentsOf: place.appending(path: "notes.txt"), encoding: .utf8) == "from the Trash")
        #expect(another.isThere)
    }

    /// A move that fails once its new name is taken gives the name back, so neither the Trash nor the place an item
    /// was being put back to keeps an empty stand-in. exFAT refuses no permission, so no rename there can be made to
    /// fail at that moment: here the startup disk plays exFAT, answering `ENOTSUP` for a free name, and a folder
    /// that cannot be changed makes the rename fail.
    @Test func aMoveThatFailsLeavesNothingBehind() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("locked/notes.txt")
        let project = try directory.directory("Project/inside")
        let trash = try directory.directory("Trash")
        let item = try OpenItem.at(file.path(percentEncoded: false)).get()
        let folderItem = try OpenItem.at(project.path(percentEncoded: false)).get()
        try directory.setPermissions(0o555, of: "locked")
        try directory.setPermissions(0o555, of: "Project")
        defer {
            try? directory.setPermissions(0o755, of: "locked")
            try? directory.setPermissions(0o755, of: "Project")
        }
        let likeExFAT: TrashMover.ExclusiveRename = { _, name, directory in
            var info = stat()
            let isTaken = name.withCString { fstatat(directory.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) } == 0
            return .failure(POSIXError(isTaken ? .EEXIST : .ENOTSUP))
        }

        let bin = try DirectoryHandle.at(trash.path(percentEncoded: false)).get()
        #expect(throws: POSIXError.self) { try TrashMover.move(item, into: bin, exclusively: likeExFAT).get() }
        #expect(throws: POSIXError.self) { try TrashMover.move(folderItem, into: bin, exclusively: likeExFAT).get() }
        #expect(try contents(of: trash).isEmpty)
        #expect(file.isThere && project.isThere)
    }
}
