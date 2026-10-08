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

    /// A program this process starts is, for a moment, a copy of this process holding its files, so it is left out
    /// with it. `fork` makes such a copy on demand.
    @Test func leavesOutACopyOfItsOwnProcess() throws {
        let directory = try TemporaryDirectory()
        let handle = try FileHandle(forReadingFrom: try directory.file("Cache/store.db"))
        defer { try? handle.close() }
        let copy = try Self.copyOfThisProcess(holdingOnly: handle.fileDescriptor)
        defer { Self.end(copy) }

        #expect(OpenFiles().holders(of: directory.url.appending(path: "Cache")).isEmpty)
    }

    /// A process running this process's program that this process did not start holds what it opens, as a second
    /// `peel` started from another terminal does.
    @Test func anotherProcessRunningItsProgramHolds() throws {
        let directory = try TemporaryDirectory()
        let handle = try FileHandle(forReadingFrom: try directory.file("Cache/store.db"))
        defer { try? handle.close() }
        let copy = try Self.copyOfThisProcess(holdingOnly: handle.fileDescriptor, madeByACopy: true)
        defer { Self.end(copy) }

        let holders = OpenFiles().holders(of: directory.url.appending(path: "Cache"))
        #expect(holders == [OpenFiles.name(of: getpid())])
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
        #expect(!OpenFiles(excluding: nil).holders(of: app, lettingItsProgramsRun: true).isEmpty)
    }

    /// Nothing is written into the app here: once a program inside it starts, macOS revokes a descriptor open for
    /// writing on a file in the app and may refuse a new one.
    @Test func aProgramRunningFromInsideAnAppHoldsItUnlessItsProgramsMayRun() throws {
        let directory = try TemporaryDirectory()
        let process = try directory.runningProgram("Example.app/Contents/Resources/daemon")
        defer { process.terminate() }
        let app = directory.url.appending(path: "Example.app", directoryHint: .isDirectory)

        #expect(OpenFiles(excluding: nil).holders(of: app) == ["daemon"])
        #expect(OpenFiles(excluding: nil).holders(of: app, lettingItsProgramsRun: true).isEmpty)
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

    /// A copy of this process that holds only `descriptor`, so no other test's files, and waits until it is killed,
    /// or for 300 s. With `madeByACopy`, a copy that already holds only `descriptor` makes it, so this process did not
    /// start it. A copy calls only C on values made before it, since another thread may have held a lock of Swift's
    /// runtime as it was made, and it never returns into the test, where it would clean up the test's folder.
    private static func copyOfThisProcess(
        holdingOnly descriptor: Int32,
        madeByACopy: Bool = false
    ) throws -> (copy: pid_t, started: pid_t) {
        // Swift marks `fork` unavailable, so it is found by name, with `RTLD_DEFAULT` (-2 in `dlfcn.h`).
        let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "fork")
        let fork = unsafeBitCast(symbol, to: (@convention(c) () -> pid_t).self)
        var ends: [Int32] = [-1, -1]
        try #require(pipe(&ends) == 0)
        let (reading, writing) = (ends[0], ends[1])
        let limit = getdtablesize()
        let size = MemoryLayout<pid_t>.size
        let started = fork()
        if started == 0 {
            var other: Int32 = 0
            while other < limit {
                if other != writing, other != descriptor { close(other) }
                other += 1
            }
            var holds = true
            if madeByACopy { holds = fork() == 0 }
            if !holds { close(descriptor) }
            alarm(300)
            var copy = getpid()
            if holds { write(writing, &copy, size) }
            while true { pause() }
        }
        close(writing)
        var copy: pid_t = 0
        let got = started > 0 ? read(reading, &copy, size) : 0
        close(reading)
        if got != size || copy <= 0 { end((copy, started)) }
        try #require(got == size && copy > 0)
        return (copy, started)
    }

    /// Ends the copies, signaling only a process: `kill` reads 0 as this process's group and -1 as every process.
    private static func end(_ copy: (copy: pid_t, started: pid_t)) {
        for process in [copy.copy, copy.started] where process > 0 {
            kill(process, SIGKILL)
        }
        if copy.started > 0 { waitpid(copy.started, nil, 0) }
    }
}
