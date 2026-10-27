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

    @Test func leavesOutACopyOfItsOwnProcess() throws {
        let directory = try TemporaryDirectory()
        let handle = try FileHandle(forReadingFrom: try directory.file("Cache/store.db"))
        defer { try? handle.close() }
        let copy = try Self.copyOfThisProcess(holdingOnly: handle.fileDescriptor)
        defer { Self.end(copy) }

        #expect(OpenFiles().holders(of: directory.url.appending(path: "Cache")).isEmpty)
    }

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

    @Test func namesAProcessByItsWholeProgramName() throws {
        let directory = try TemporaryDirectory()
        let name = "org.example.agent.with.a.long.program.name"
        let process = try directory.runningProgram("Example.app/Contents/MacOS/\(name)")
        defer { process.terminate() }

        #expect(OpenFiles.name(of: process.processIdentifier) == name)
    }

    /// An app extension runs on its app's behalf and macOS ends it once the app goes, so it holds nothing.
    @Test func anAppExtensionRunningFromInsideAnAppHoldsNothing() throws {
        let directory = try TemporaryDirectory()
        let process = try directory.runningProgram("Example.app/Contents/PlugIns/Share.appex/Contents/MacOS/share")
        defer { process.terminate() }

        #expect(OpenFiles(excluding: nil).holders(of: directory.url.appending(path: "Example.app")).isEmpty)
    }

    @Test func namesMacOSWhenOnlyItsOwnProgramsHoldAnItem() throws {
        let directory = try TemporaryDirectory()
        let log = try directory.file("Cache/stats.log")
        let iostat = try Self.macOSProgram(writingTo: log)
        defer { iostat.terminate() }

        let refusal = OpenFiles().refusal(of: log.deletingLastPathComponent(), lettingItsProgramsRun: false)
        #expect(refusal == .inUseByMacOS(by: ["iostat"]))
    }

    @Test func leavesMacOSOutWhileAProgramThatCanQuitHoldsTheItemToo() throws {
        let directory = try TemporaryDirectory()
        let log = try directory.file("Support/stats.log")
        let iostat = try Self.macOSProgram(writingTo: log)
        defer { iostat.terminate() }
        let agent = try directory.runningProgram("Support/agent")
        defer { agent.terminate() }

        let refusal = OpenFiles().refusal(of: log.deletingLastPathComponent(), lettingItsProgramsRun: false)
        #expect(refusal == .heldOpen(by: ["agent"]))
    }

    @Test func tellsAnotherUserOfThisMacFromTheSystem() {
        #expect(OpenFiles.owner(ofAccount: 0) == .system)
        #expect(OpenFiles.owner(ofAccount: 89) == .system)
        #expect(OpenFiles.owner(ofAccount: uid_t(bitPattern: -2)) == .system)
        #expect(OpenFiles.owner(ofAccount: nil) == .system)
        #expect(OpenFiles.owner(ofAccount: 502) == .anotherUser)
        #expect(OpenFiles.uid(of: 1) == 0)
        #expect(OpenFiles.uid(of: getpid()) == getuid())
    }

    @Test func anAppOpenInAnotherUsersAccountIsQuitThereNotInBackgroundItems() {
        let open = OpenFiles.Holder(process: "Spotify", owner: .anotherUser, isMacOSsOwn: false)
        let daemon = OpenFiles.Holder(process: "updater", owner: .system, isMacOSsOwn: false)
        let mine = OpenFiles.Holder(process: "agent", owner: .thisAccount, isMacOSsOwn: false)

        #expect(OpenFiles.refusal(heldBy: [open, daemon]) == .openForAnotherUser(by: ["Spotify"]))
        #expect(OpenFiles.refusal(heldBy: [daemon]) == .heldByAnotherAccount(by: ["updater"]))
        #expect(OpenFiles.refusal(heldBy: [mine]) == .heldOpen(by: ["agent"]))
        #expect(OpenFiles.refusal(heldBy: []) == nil)
    }

    @Test func aBuildToolsDaemonIsNamedByItsToolWithTheCommandThatStopsIt() throws {
        let directory = try TemporaryDirectory()
        let log = try directory.file("home/.gradle/daemon/9.2/daemon-1.out.log")
        let main = "org.gradle.launcher.daemon.bootstrap.GradleDaemon"
        let daemon = try Self.program("jdk/bin/java", in: directory, arguments: ["-", main, "9.2"], writingTo: log)
        defer { daemon.terminate() }

        let refusal = OpenFiles().refusal(of: log.deletingLastPathComponent(), lettingItsProgramsRun: false)

        #expect(OpenFiles.arguments(of: daemon.processIdentifier)?.suffix(3) == ["-", main, "9.2"])
        #expect(refusal == .heldByABuildTool(by: ["Gradle"]))
    }

    @Test func anInputSourceInUseIsRemovedInSystemSettings() throws {
        let directory = try TemporaryDirectory()
        let programs = try directory.runningPrograms([
            "home/Library/Input Methods/Example.app/Contents/MacOS/example",
            "home/Library/Application Support/Example.app/Contents/MacOS/example",
        ])
        defer { programs.forEach { $0.terminate() } }
        let files = OpenFiles()

        let inputSource = directory.url.appending(path: "home/Library/Input Methods/Example.app")
        let elsewhere = directory.url.appending(path: "home/Library/Application Support/Example.app")
        #expect(files.refusal(of: inputSource, lettingItsProgramsRun: false) == .inUseAsAnInputSource)
        #expect(files.refusal(of: elsewhere, lettingItsProgramsRun: false) == .heldOpen(by: ["example"]))
    }

    @Test func aScriptAProgramRunsHoldsTheFolderItRunsFrom() throws {
        let directory = try TemporaryDirectory()
        let script = try directory.file("home/.npm/_npx/0123abcd/node_modules/.bin/server")
        let errors = try directory.file("errors.log")
        let arguments = ["-", script.path(percentEncoded: false)]
        let node = try Self.program("bin/node", in: directory, arguments: arguments, writingTo: errors)
        defer { node.terminate() }
        let viewer = try Self.program("bin/viewer", in: directory, arguments: arguments, writingTo: errors)
        defer { viewer.terminate() }

        let refusal = OpenFiles().refusal(of: directory.url.appending(path: "home/.npm/_npx"), lettingItsProgramsRun: false)

        #expect(refusal == .heldOpen(by: ["node"]))
    }

    @Test func knowsEachBuildToolsDaemonByHowTheToolStartsIt() {
        let gradle = ["/jdk/bin/java", "-Xmx512m", "-cp", "/x/gradle-launcher-9.2.jar",
                      "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "9.2"]
        let kotlin = ["/jdk/bin/java", "-cp", "/x/kotlin-compiler-embeddable.jar",
                      "org.jetbrains.kotlin.daemon.KotlinCompileDaemon", "--daemon-runFilesPath=/x"]
        let bazel = ["bazel(project)", "-Xverify:none", "-jar", "/x/install/0123/A-server.jar", "--output_base=/x"]
        let mvnd = ["/jdk/bin/java", "-Dmvnd.id=5a2c", "org.codehaus.plexus.classworlds.launcher.Launcher"]
        let maven = ["/jdk/bin/java", "org.codehaus.plexus.classworlds.launcher.Launcher", "install"]

        #expect(BuildDaemon.running(with: gradle) == .gradle)
        #expect(BuildDaemon.running(with: kotlin) == .kotlin)
        #expect(BuildDaemon.running(with: bazel) == .bazel)
        #expect(BuildDaemon.running(with: mvnd) == .mavenDaemon)
        #expect(BuildDaemon.running(with: maven) == nil)
        #expect(BuildDaemon.allCases.map(\.stop) == ["gradle --stop", "gradle --stop", "bazel shutdown", "mvnd --stop"])
    }

    @Test func knowsMacOSsOwnProgramsByWhereTheyRun() {
        let macOSs = [
            "/usr/libexec/appleaccountd", "/usr/sbin/cfprefsd", "/sbin/launchd",
            "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/mdworker_shared",
            "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock",
            "/System/Volumes/Preboot/Cryptexes/App/usr/libexec/webpushd",
            "/System/iOSSupport/System/Library/PrivateFrameworks/HomeEnergyDaemon.framework/Support/homeenergyd",
            "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/XPCServices/XProtectPluginService.xpc/Contents/MacOS/XProtectPluginService",
        ]
        let thePersons = [
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari",
            "/System/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari",
            "/System/Applications/Utilities/Console.app/Contents/MacOS/Console",
            "/System/Library/CoreServices/Applications/Archive Utility.app/Contents/MacOS/Archive Utility",
            "/System/Volumes/Data/Applications/Example.app/Contents/MacOS/Example",
            "/usr/bin/tail", "/bin/zsh", "/usr/local/bin/node", "/Applications/Example.app/Contents/MacOS/Example",
        ]

        #expect(macOSs.filter { !OpenFiles.isMacOSsOwn($0) } == [])
        #expect(thePersons.filter(OpenFiles.isMacOSsOwn) == [])
    }

    /// A copy of `cat` at `path`, started with `arguments` and holding `file` open for writing as its error output. It
    /// echoes a line before this returns, so macOS has let it run, and reads its input until the test closes it.
    private static func program(
        _ path: String, in directory: borrowing TemporaryDirectory, arguments: [String], writingTo file: URL
    ) throws -> Process {
        let program = directory.url.appending(path: path)
        try FileManager.default.createDirectory(
            at: program.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: URL(filePath: "/bin/cat"), to: program)
        let signing = try Process.run(
            URL(filePath: "/usr/bin/codesign"), arguments: ["--force", "--sign", "-", program.path(percentEncoded: false)]
        )
        signing.waitUntilExit()
        let input = Pipe()
        let output = Pipe()
        let errors = try FileHandle(forWritingTo: file)
        defer { try? errors.close() }
        let line = Data("running\n".utf8)
        try input.fileHandleForWriting.write(contentsOf: line)
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        guard try output.fileHandleForReading.read(upToCount: line.count) == line else {
            throw CocoaError(.executableLoad, userInfo: [NSFilePathErrorKey: program.path])
        }
        return process
    }

    /// `iostat`, run from where macOS keeps it, writing into `file`, which it holds open until it ends five minutes on.
    private static func macOSProgram(writingTo file: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/iostat")
        process.arguments = ["-w", "300", "-c", "2"]
        let output = try FileHandle(forWritingTo: file)
        defer { try? output.close() }
        process.standardOutput = output
        try process.run()
        return process
    }

    /// A copy of this process holding only `descriptor`, made by another copy when `madeByACopy`. A copy calls only C:
    /// another thread may have held a lock of Swift's runtime, and returning into the test would run its cleanup.
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
