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

        let holders = OpenFiles(excluding: nil).holders(of: folder)
        #expect(holders.isEmpty, "held by \(holders)")
    }

    @Test func leavesOutItsOwnProcess() throws {
        let directory = try TemporaryDirectory()
        let handle = try FileHandle(forReadingFrom: try directory.file("Cache/store.db"))
        defer { try? handle.close() }

        #expect(OpenFiles().holders(of: directory.url.appending(path: "Cache")).isEmpty)
    }

    /// A program running from inside a folder holds it, as an agent an app keeps in its support folder does.
    @Test func seesAProgramRunningFromInsideAFolder() throws {
        let directory = try TemporaryDirectory()
        let tool = try directory.directory("Support/Agent.app/Contents/MacOS").appending(path: "agent")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: tool.path(percentEncoded: false))
        let process = Process()
        process.executableURL = tool
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }

        let folder = directory.url.appending(path: "Support", directoryHint: .isDirectory)
        #expect(OpenFiles(excluding: nil).holders(of: folder) == ["agent"])
    }

    /// A process of another account, root's included, can't be asked its name, but the program it runs says it.
    @Test func namesAProcessOfAnotherAccountByItsProgram() {
        #expect(OpenFiles.name(of: 1) == "launchd")
    }

    /// An app extension runs on its app's behalf and macOS ends it once the app goes, so it holds nothing.
    @Test func anAppExtensionRunningFromInsideAnAppHoldsNothing() throws {
        let directory = try TemporaryDirectory()
        let tool = try directory.directory("Example.app/Contents/PlugIns/Share.appex/Contents/MacOS")
            .appending(path: "share")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: tool.path(percentEncoded: false))
        let process = Process()
        process.executableURL = tool
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }

        #expect(OpenFiles(excluding: nil).holders(of: directory.url.appending(path: "Example.app")).isEmpty)
    }
}
