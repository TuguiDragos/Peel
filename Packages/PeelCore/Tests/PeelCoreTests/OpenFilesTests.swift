import Darwin
import Foundation
@testable import PeelCore
import Testing

struct OpenFilesTests {
    @Test func seesAFileHeldOpenInsideAFolder() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("Cache/inner/store.db")
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        let folder = directory.url.appending(path: "Cache", directoryHint: .isDirectory)
        #expect(!OpenFiles(excluding: nil).holders(of: folder).isEmpty)
        #expect(!OpenFiles(excluding: nil).holders(of: file).isEmpty)
        #expect(OpenFiles(excluding: nil).holders(of: directory.url.appending(path: "Other")).isEmpty)
    }

    @Test func aWatchOrAnOpenFolderHoldsNothing() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("Cache/store.db")
        let folder = file.deletingLastPathComponent()
        let watch = open(file.path(percentEncoded: false), O_EVTONLY)
        let opened = open(folder.path(percentEncoded: false), O_RDONLY)
        defer { close(watch); close(opened) }
        #expect(watch >= 0 && opened >= 0)

        #expect(OpenFiles(excluding: nil).holders(of: folder).isEmpty)
    }

    @Test func leavesOutItsOwnProcess() throws {
        let directory = try TemporaryDirectory()
        let handle = try FileHandle(forReadingFrom: try directory.file("Cache/store.db"))
        defer { try? handle.close() }

        #expect(OpenFiles().holders(of: directory.url.appending(path: "Cache")).isEmpty)
    }
}
