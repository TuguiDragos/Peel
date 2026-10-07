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
        let process = try directory.runningProgram("Support/Agent.app/Contents/MacOS/agent")
        defer { process.terminate() }

        let folder = directory.url.appending(path: "Support", directoryHint: .isDirectory)
        #expect(OpenFiles(excluding: nil).holders(of: folder) == ["agent"])
    }

    /// Inside an app, a file another program only reads holds nothing, as Safari reads the code of an app's Safari
    /// extension: code loses nothing when it moves. A file open for writing still holds the app.
    @Test func insideAnAppOnlyAFileOpenForWritingHoldsIt() throws {
        let directory = try TemporaryDirectory()
        let code = try directory.file("Example.app/Contents/PlugIns/Open.appex/Contents/MacOS/Open")
        let state = try directory.file("Example.app/Contents/Resources/state.db")
        let app = directory.url.appending(path: "Example.app", directoryHint: .isDirectory)
        let reading = try FileHandle(forReadingFrom: code)
        defer { try? reading.close() }

        #expect(OpenFiles(excluding: nil).holders(of: app).isEmpty)

        let writing = try FileHandle(forWritingTo: state)
        defer { try? writing.close() }
        #expect(!OpenFiles(excluding: nil).holders(of: app).isEmpty)
    }

    @Test func aProgramRunningFromInsideAnAppHoldsItUnlessItsProgramsMayRun() throws {
        let directory = try TemporaryDirectory()
        let process = try directory.runningProgram("Example.app/Contents/Resources/daemon")
        defer { process.terminate() }
        let state = try directory.file("Example.app/Contents/Resources/state.db")
        let app = directory.url.appending(path: "Example.app", directoryHint: .isDirectory)

        #expect(OpenFiles(excluding: nil).holders(of: app) == ["daemon"])
        #expect(OpenFiles(excluding: nil).holders(of: app, lettingItsProgramsRun: true).isEmpty)

        let writing = try FileHandle(forWritingTo: state)
        defer { try? writing.close() }
        #expect(!OpenFiles(excluding: nil).holders(of: app, lettingItsProgramsRun: true).isEmpty)
    }

    /// A process of another account, root's included, can't be asked its name, but the program it runs says it.
    @Test func namesAProcessOfAnotherAccountByItsProgram() {
        #expect(OpenFiles.name(of: 1) == "launchd")
    }

    /// An app extension runs on its app's behalf and macOS ends it once the app goes, so it holds nothing.
    @Test func anAppExtensionRunningFromInsideAnAppHoldsNothing() throws {
        let directory = try TemporaryDirectory()
        let process = try directory.runningProgram("Example.app/Contents/PlugIns/Share.appex/Contents/MacOS/share")
        defer { process.terminate() }

        #expect(OpenFiles(excluding: nil).holders(of: directory.url.appending(path: "Example.app")).isEmpty)
    }
}
