import Foundation
import Synchronization
@testable import PeelCore
import PeelPrivileged
import Testing

struct TrashServiceTests {
    /// An item is in the Trash when it sits there or in a folder there. Put Back asks the narrower question, since
    /// what it puts back sits directly in a Trash, and a folder that is only called `.Trash` is no Trash.
    @Test func knowsWhatIsInATrashDirectlyOrInAFolderThere() throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let direct = try directory.directory("home/.Trash/Example.app")
        let nested = try directory.directory("home/.Trash/Old Apps/Example.app")
        let installed = try directory.directory("home/Applications/Example.app")
        let lookalike = try directory.directory("home/Documents/.Trash/Example.app")

        #expect(service.isInsideATrash(direct))
        #expect(service.isInsideATrash(nested))
        #expect(!service.isInsideATrash(installed))
        #expect(!service.isInsideATrash(lookalike))
        #expect(service.isInATrash(direct))
        #expect(!service.isInATrash(nested))
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        for url in [direct, nested, installed, lookalike] {
            #expect(TrashService.isInsideATrash(url, home: home) == service.isInsideATrash(url), "\(url.path)")
        }
    }

    private func service(in directory: borrowing TemporaryDirectory) throws -> TrashService {
        // Where macOS keeps it, because restore refuses an item that is not really in a Trash.
        let trash = try directory.directory("home/.Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(environment: environment) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    @Test func asksTheCallersQuestionBesideEachMove() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let first = try directory.file("home/Documents/first.txt")
        let second = try directory.file("home/Documents/second.txt")
        let third = try directory.file("home/Documents/third.txt")
        let asked = Mutex<[URL]>([])

        let result = await service.trash([first, second, third]) { url in
            asked.withLock { $0.append(url) }
            return url == second ? .changedSinceScan : nil
        }

        #expect(asked.withLock { $0 } == [first, second, third])
        #expect(result.trashed.map(\.originalURL) == [first, third])
        #expect(result.failures.map(\.url) == [second])
        #expect(result.failures.map(\.reason) == [.changedSinceScan])
        #expect(FileManager.default.fileExists(atPath: second.path(percentEncoded: false)))
    }

    /// Records the jobs launchd would have been asked to stop, since a test never asks launchd.
    private actor Stopped {
        private(set) var labels: [String] = []

        func record(_ jobs: [LaunchdCleanup.Job]) -> [LaunchdCleanup.Job] {
            labels += jobs.map(\.label)
            return jobs
        }
    }

    private func launchdPlist(_ path: String, in directory: borrowing TemporaryDirectory) throws -> URL {
        let label = URL(filePath: path).deletingPathExtension().lastPathComponent
        return try directory.file(
            path,
            contents: PropertyListSerialization.data(fromPropertyList: ["Label": label], format: .xml, options: 0)
        )
    }

    /// A service that moves everything except `stuck` into the test's own Trash, both as the user and through
    /// the helper. The jobs it would stop are recorded in `stopped`.
    private func service(
        in directory: borrowing TemporaryDirectory,
        stopped: Stopped,
        stuck: URL
    ) throws -> TrashService {
        let trash = try directory.directory("home/.Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let move: @Sendable (URL) throws -> URL = { url in
            guard url != stuck else { throw CocoaError(.fileWriteNoPermission) }
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        return TrashService(
            environment: environment,
            stopJobs: { jobs, _ in await stopped.record(jobs) },
            moveThroughHelper: { urls in
                var result = TrashResult()
                for url in urls {
                    do {
                        result.trashed.append(TrashedItem(originalURL: url, trashedURL: try move(url), date: .now))
                    } catch {
                        result.failures.append(TrashFailure(url: url, reason: .notPermitted))
                    }
                }
                return result
            },
            moveToTrash: move
        )
    }

    /// What launchd would have been asked, since a test never asks launchd: the jobs stopped, which end their process
    /// unless `endsTheProcess` is false, and the jobs started again.
    private actor Launchd {
        private(set) var stopped: [String] = []
        private(set) var started: [String] = []
        let endsTheProcess: Bool

        init(endsTheProcess: Bool = true) {
            self.endsTheProcess = endsTheProcess
        }

        func stop(_ jobs: [LaunchdCleanup.Running], ending process: Process) async -> [LaunchdCleanup.Running] {
            stopped += jobs.map(\.label)
            guard endsTheProcess else { return jobs }
            let ends = ProcessEnds.of([process.processIdentifier])
            process.terminate()
            for await _ in ends {}
            return jobs
        }

        func start(_ job: LaunchdCleanup.Job) {
            started.append(job.label)
        }
    }

    private func appRunningItsAgent(
        in directory: borrowing TemporaryDirectory
    ) throws -> (app: URL, agent: Process, plist: URL, job: LaunchdCleanup.Running) {
        let agent = try directory.runningProgram("root/Applications/Agentful.app/Contents/MacOS/agent")
        let plist = try launchdPlist("home/Library/LaunchAgents/org.example.agentful.agent.plist", in: directory)
        let job = LaunchdCleanup.Running(
            label: "org.example.agentful.agent", isDaemon: false, pid: agent.processIdentifier, plist: plist
        )
        return (directory.url.appending(path: "root/Applications/Agentful.app", directoryHint: .isDirectory), agent, plist, job)
    }

    private func service(
        in directory: borrowing TemporaryDirectory,
        launchd: Launchd,
        agent: Process,
        running: [LaunchdCleanup.Running]
    ) throws -> TrashService {
        let trash = try directory.directory("home/.Trash")
        return TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            startJob: { job, _ in await launchd.start(job) },
            runningInside: { _ in running },
            stopRunning: { jobs, _ in await launchd.stop(jobs, ending: agent) }
        ) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    @Test func stopsTheAppsOwnBackgroundProgramThenMovesTheAppAndItsFiles() async throws {
        let directory = try TemporaryDirectory()
        let (app, agent, plist, job) = try appRunningItsAgent(in: directory)
        defer { agent.terminate() }
        let launchd = Launchd()
        let service = try service(in: directory, launchd: launchd, agent: agent, running: [job])

        let result = await service.trash(
            apps: [app], thenFiles: { stayed in stayed.isEmpty ? [plist] : [] }, usingHelperFor: [],
            lettingTheirProgramsRun: []
        )

        #expect(Set(result.trashed.map(\.originalURL)) == [app, plist])
        #expect(result.failures.isEmpty)
        #expect(result.trashed.first { $0.originalURL == plist }?.stoppedJob == job.label)
        #expect(await launchd.stopped == [job.label])
        #expect(await launchd.started.isEmpty)
    }

    @Test func stopsNothingWhileAProgramThatIsNotTheAppsJobHoldsIt() async throws {
        let directory = try TemporaryDirectory()
        let (app, agent, plist, _) = try appRunningItsAgent(in: directory)
        defer { agent.terminate() }
        let launchd = Launchd()
        let service = try service(in: directory, launchd: launchd, agent: agent, running: [])

        let result = await service.trash(
            apps: [app], thenFiles: { stayed in stayed.isEmpty ? [plist] : [] }, usingHelperFor: [],
            lettingTheirProgramsRun: []
        )

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.url) == [app])
        #expect(await launchd.stopped.isEmpty)
    }

    @Test func startsAgainWhatItStoppedWhenTheAppStillStays() async throws {
        let directory = try TemporaryDirectory()
        let (app, agent, plist, job) = try appRunningItsAgent(in: directory)
        defer { agent.terminate() }
        let launchd = Launchd(endsTheProcess: false)
        let service = try service(in: directory, launchd: launchd, agent: agent, running: [job])

        let result = await service.trash(
            apps: [app], thenFiles: { stayed in stayed.isEmpty ? [plist] : [] }, usingHelperFor: [],
            lettingTheirProgramsRun: []
        )

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.url) == [app])
        #expect(await launchd.started == [job.label])
    }

    @Test func startsAgainAJobWhoseFileStaysOnceTheAppMoved() async throws {
        let directory = try TemporaryDirectory()
        let (app, agent, _, job) = try appRunningItsAgent(in: directory)
        defer { agent.terminate() }
        let launchd = Launchd()
        let service = try service(in: directory, launchd: launchd, agent: agent, running: [job])

        let result = await service.trash(
            apps: [app], thenFiles: { _ in [] }, usingHelperFor: [], lettingTheirProgramsRun: []
        )

        #expect(result.trashed.map(\.originalURL) == [app])
        #expect(await launchd.started == [job.label])
    }

    @Test func resetsThePrivacyOfAnAppOnlyItsOwnBackgroundProgramKeepsInPlace() async throws {
        let directory = try TemporaryDirectory()
        let (app, agent, _, job) = try appRunningItsAgent(in: directory)
        defer { agent.terminate() }
        let installed = InstalledApp(url: app, bundleIdentifier: "org.example.agentful", name: "Agentful")
        let stopsItsJob = try service(in: directory, launchd: Launchd(), agent: agent, running: [job])
        let findsNoJob = try service(in: directory, launchd: Launchd(), agent: agent, running: [])

        #expect(await PrivacyReset.goingNow([installed], with: stopsItsJob) == [installed])
        #expect(await PrivacyReset.goingNow([installed], with: findsNoJob).isEmpty)
    }

    /// A command-line tool's link, and its shell completion's, lead into its app until the app has moved, and the
    /// helper takes such a link only once it leads nowhere, so the links go to the helper after everything else, in
    /// whatever order they came.
    @Test func sendsAToolsLinkToTheHelperAfterTheAppItLeadsInto() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("root/Applications/Tool.app")
        try directory.directory("root/usr/local/bin")
        try directory.directory("root/usr/local/share/zsh/site-functions")
        let link = directory.url.appending(path: "root/usr/local/bin/tool")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app.appending(path: "Contents/MacOS/tool"))
        let completion = directory.url.appending(path: "root/usr/local/share/zsh/site-functions/_tool")
        try FileManager.default.createSymbolicLink(at: completion, withDestinationURL: app.appending(path: "Contents/Resources/_tool"))
        let batches = Mutex<[[String]]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            moveThroughHelper: { urls in
                batches.withLock { $0.append(urls.map(\.lastPathComponent)) }
                return TrashResult(trashed: urls.map { TrashedItem(originalURL: $0, trashedURL: $0, date: .now) })
            },
            moveToTrash: { _ in throw CocoaError(.fileWriteNoPermission) }
        )

        _ = await service.trash([link, completion, app], usingHelperFor: [link, completion, app])
        #expect(batches.withLock { $0 } == [["Tool.app"], ["tool", "_tool"]])
    }

    /// An item inside a folder that just moved went with it, whatever its name begins with: it is neither moved
    /// again nor a failure. A slash and a combining mark after it are one `Character`, so to a comparison of
    /// characters such an item was not inside its folder, and its move failed for a file already in the Trash.
    @Test func anItemInsideAFolderThatMovedWentWithItWhateverItsNameBeginsWith() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("home/Library/Caches/com.example.app")
        let inside = try directory.file("home/Library/Caches/com.example.app/\u{301}cache.db")

        let result = try await service(in: directory).trash([folder, inside])

        #expect(result.trashed.map(\.originalURL) == [folder])
        #expect(result.failures.isEmpty, "the item inside the folder was moved again: \(result.failures)")
    }

    /// A long removal says how far it got: every item that moved counts once, and one that stays counts nothing.
    @Test func countsWhatMovedForWhoeverWatches() async throws {
        let directory = try TemporaryDirectory()
        let first = try directory.directory("home/Library/Caches/org.example.one")
        let second = try directory.directory("home/Library/Caches/org.example.two")
        let keychain = try directory.file("home/Library/Keychains/login.keychain-db")
        let count = MoveCount()

        let service = try service(in: directory)
        let result = await MoveCount.$current.withValue(count) {
            await service.trash([first, second, keychain])
        }

        #expect(result.trashed.count == 2)
        #expect(count.value == 2)
    }

    /// A job stopped before a move that then fails is a job left stopped with its file still in place.
    @Test func stopsAJobOnlyOnceItsFileHasMoved() async throws {
        let directory = try TemporaryDirectory()
        let moved = try launchdPlist("home/Library/LaunchAgents/com.example.moved.plist", in: directory)
        let stuck = try launchdPlist("home/Library/LaunchAgents/com.example.stuck.plist", in: directory)
        let stopped = Stopped()

        let result = try await service(in: directory, stopped: stopped, stuck: stuck).trash([moved, stuck])

        #expect(result.trashed.map(\.originalURL) == [moved])
        #expect(await stopped.labels == ["com.example.moved"])
        #expect(result.trashed.map(\.stoppedJob) == ["com.example.moved"])
    }

    /// An item that needs the helper but was not selected stays in place, and its job keeps running.
    @Test func leavesTheJobsOfUnselectedItemsRunning() async throws {
        let directory = try TemporaryDirectory()
        let selected = try launchdPlist("root/Library/LaunchDaemons/com.example.selected.plist", in: directory)
        let stuck = try launchdPlist("root/Library/LaunchDaemons/com.example.stuck.plist", in: directory)
        let unselected = try launchdPlist("root/Library/LaunchAgents/com.example.shared.plist", in: directory)
        let stopped = Stopped()

        let result = try await service(in: directory, stopped: stopped, stuck: stuck)
            .trash([selected, stuck], usingHelperFor: [selected, stuck, unselected])

        #expect(result.trashed.map(\.originalURL) == [selected])
        #expect(await stopped.labels == ["com.example.selected"])
        #expect(result.trashed.map(\.stoppedJob) == ["com.example.selected"])
        #expect(FileManager.default.fileExists(atPath: unselected.path(percentEncoded: false)))
    }

    @Test func puttingBackTheFileOfAJobPeelStoppedStartsItAgain() async throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        let running = try launchdPlist("home/Library/LaunchAgents/org.example.running.plist", in: directory)
        let idle = try launchdPlist("home/Library/LaunchAgents/org.example.idle.plist", in: directory)
        let started = Mutex<[String]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            ),
            stopJobs: { jobs, _ in jobs.filter { $0.label == "org.example.running" } },
            startJob: { job, _ in started.withLock { $0.append(job.label) } },
            moveToTrash: { url in
                let destination = trash.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        let result = await service.trash([running, idle])
        #expect(started.withLock { $0 }.isEmpty)
        for item in result.trashed {
            let record = RemovalRecord(batch: UUID(), item: item, size: nil, source: "Example", tool: "test")
            let read = try JSONDecoder().decode(RemovalRecord.self, from: JSONEncoder().encode(record))
            #expect(await service.restore(read.trashedItem) == nil)
        }

        #expect(started.withLock { $0 } == ["org.example.running"], "the job Peel stopped was not started again")
        #expect(running.isThere && idle.isThere)
    }

    @Test func aJobIsStartedAgainOnlyAsTheFilePutBackDeclaresIt() async throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        let plist = try launchdPlist("home/Library/LaunchAgents/org.example.agent.plist", in: directory)
        let trashed = trash.appending(path: plist.lastPathComponent)
        try FileManager.default.moveItem(at: plist, to: trashed)
        let started = Mutex<[String]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            ),
            startJob: { job, _ in started.withLock { $0.append(job.label) } },
            moveToTrash: { $0 }
        )

        let edited = TrashedItem(originalURL: plist, trashedURL: trashed, date: .now, stoppedJob: "org.example.other")
        #expect(await service.restore(edited) == nil)
        #expect(started.withLock { $0 }.isEmpty, "a label History named, and the file does not declare, was started")
    }

    /// The guard and the exclusions decide before any job is stopped. What they keep is never moved, so its job
    /// is never stopped either.
    @Test func leavesTheJobOfAnExcludedItemRunning() async throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        let kept = try launchdPlist("home/Library/LaunchAgents/com.example.kept.plist", in: directory)
        let going = try launchdPlist("home/Library/LaunchAgents/com.example.going.plist", in: directory)
        let stopped = Stopped()
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            ),
            exclusions: Exclusions(paths: [kept]),
            stopJobs: { jobs, _ in await stopped.record(jobs) },
            moveToTrash: { url in
                let destination = trash.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        let result = await service.trash([kept, going])

        #expect(result.failures == [TrashFailure(url: kept, reason: .guarded(.excluded))])
        #expect(await stopped.labels == ["com.example.going"])
        #expect(kept.isThere)
    }

    private actor Forgotten {
        private(set) var calls: [[String]] = []

        func record(_ urls: [URL], owner: String?) {
            calls.append(urls.map { $0.pathComponents.suffix(4).joined(separator: "/") } + [owner ?? "no owner"])
        }
    }

    /// `defaults delete` costs a process per domain, so each file that moved is passed on once, by whichever
    /// move took it (Peel's own or the helper's). A file that did not move is not passed on.
    @Test func forgetsTheDomainsOfWhatMovedOnce() async throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        let settings = try directory.file("home/Library/Preferences/com.example.app.plist")
        let shared = try directory.file("root/Library/Preferences/com.example.app.plist")
        let stuck = try directory.file("home/Library/Preferences/com.example.stuck.plist")
        let forgotten = Forgotten()
        let move: @Sendable (URL) throws -> URL = { url in
            guard url != stuck else { throw CocoaError(.fileWriteNoPermission) }
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            ),
            forgetDomains: { await forgotten.record($0, owner: $1) },
            moveThroughHelper: { urls in
                TrashResult(
                    trashed: urls.compactMap { url in
                        (try? move(url)).map { TrashedItem(originalURL: url, trashedURL: $0, date: .now) }
                    }
                )
            },
            moveToTrash: move
        )

        _ = await service.trash([settings, stuck, shared], usingHelperFor: [shared])
        #expect(await forgotten.calls == [
            ["home/Library/Preferences/com.example.app.plist", "no owner"],
            ["root/Library/Preferences/com.example.app.plist", "no owner"],
        ])

        let again = try directory.file("home/Library/Preferences/com.example.app.plist")
        _ = await service.trash([again], ownedBy: "com.example.app")
        #expect(await forgotten.calls.last == ["home/Library/Preferences/com.example.app.plist", "com.example.app"])
    }

    @Test func anAppPutBackIsRegisteredWithLaunchServicesOnceItIsBack() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/org.example.Studio.app")
        let cache = try directory.directory("home/Library/Caches/org.example.Studio")
        let trash = try directory.directory("home/.Trash")
        let registered = Mutex<[String]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            registerApp: { url in registered.withLock { $0.append(url.path(percentEncoded: false)) } }
        ) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let moved = await service.trash([app, cache]).trashed
        #expect(registered.withLock { $0 }.isEmpty)
        #expect(await service.restore(moved) == [nil, nil])
        let appMoved = try #require(moved.first { $0.originalURL == app })
        #expect(await service.restore([appMoved]) == [.missingFromTrash])
        #expect(registered.withLock { $0 } == [app.path(percentEncoded: false)])
    }

    @Test func registersTheAppsPutBackOnlyOnceEveryItemIsBack() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/org.example.Studio.app")
        let container = try directory.directory("home/Library/Containers/org.example.Studio.Extension")
        let trash = try directory.directory("home/.Trash")
        let containerWasBack = Mutex<[Bool]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            registerApp: { _ in
                let isBack = FileManager.default.fileExists(atPath: container.path(percentEncoded: false))
                containerWasBack.withLock { $0.append(isBack) }
            }
        ) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let moved = await service.trash([app, container]).trashed
        let appFirst = moved.sorted { ($0.originalURL == app ? 0 : 1) < ($1.originalURL == app ? 0 : 1) }
        #expect(await service.restore(appFirst) == [nil, nil])
        #expect(containerWasBack.withLock { $0 } == [true])
    }

    /// Putting an app back puts back the Dock tiles an uninstall took out for it, and only once it is back.
    @Test func puttingAnItemBackPutsBackItsDockTiles() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/org.example.Studio.app")
        let trash = try directory.directory("home/.Trash")
        let asked = Mutex<[String]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            putBackDockTiles: { urls in asked.withLock { $0.append(contentsOf: urls.map(\.lastPathComponent)) } }
        ) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let moved = try #require(await service.trash([app]).trashed.first)
        #expect(asked.withLock { $0 }.isEmpty)
        #expect(await service.restore([moved]) == [nil])
        #expect(await service.restore([moved]) != [nil])
        #expect(asked.withLock { $0 } == ["org.example.Studio.app"])
    }

    @Test func movesItemsToTrashAndRestoresThem() async throws {
        let directory = try TemporaryDirectory()
        let item = try directory.file("home/Library/Caches/com.example.app/cache.db")
        let folder = item.deletingLastPathComponent()
        let service = try service(in: directory)

        let result = await service.trash([folder])
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))

        let failure = await service.restore(try #require(result.trashed.first))
        #expect(failure == nil)
        #expect(FileManager.default.fileExists(atPath: item.path(percentEncoded: false)))

        let missing = TrashedItem(originalURL: folder, trashedURL: directory.url.appending(path: "home/.Trash/gone"), date: .now)
        #expect(await service.restore(missing) == .missingFromTrash)

        // Records come from a file on disk, so one naming something that was never in a Trash is refused outright.
        let planted = TrashedItem(originalURL: folder, trashedURL: directory.url.appending(path: "payload"), date: .now)
        #expect(await service.restore(planted) == .notInATrash)
    }

    @Test(.permissionsHold) func saysAtOnceWhatTheHelperKeepsOutOfAFolderCodeIsLoadedFrom() throws {
        let directory = try TemporaryDirectory()
        let components = try directory.directory("root/Library/Audio/Plug-Ins/Components")
        let trashed = try directory.directory("home/.Trash/Synth.component")
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            )
        ) { $0 }
        let item = TrashedItem(originalURL: components.appending(path: "Synth.component"), trashedURL: trashed, date: .now)

        let byThePerson = service.refusal(ofPuttingBack: item, canUseHelper: true)
        try directory.setPermissions(0o555, of: components)
        defer { try? directory.setPermissions(0o755, of: components) }
        let throughTheHelper = service.refusal(ofPuttingBack: item, canUseHelper: true)

        #expect(byThePerson == nil)
        #expect(throughTheHelper == .failed(PrivilegedPathPolicy.Rejection.loadsCode.explanation))
    }

    @Test func anItemLockedInTheTrashOrAFolderLockedOnItsWayBackIsSaidSo() async throws {
        let directory = try TemporaryDirectory()
        let documents = try directory.directory("home/Documents")
        let trashed = try directory.file("home/.Trash/notes.txt", bytes: 1)
        let otherTrashed = try directory.file("home/.Trash/letter.txt", bytes: 1)
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            )
        ) { $0 }
        let locked = TrashedItem(originalURL: documents.appending(path: "notes.txt"), trashedURL: trashed, date: .now)
        let intoALockedFolder = TrashedItem(
            originalURL: documents.appending(path: "letter.txt"), trashedURL: otherTrashed, date: .now
        )
        func lock(_ url: URL, _ isLocked: Bool) throws {
            try FileManager.default.setAttributes([.immutable: isLocked], ofItemAtPath: url.path(percentEncoded: false))
        }

        try lock(trashed, true)
        let lockedItem = await service.restore(locked)
        try lock(trashed, false)
        try lock(documents, true)
        let lockedFolder = await service.restore(intoALockedFolder)
        try lock(documents, false)

        #expect(lockedItem == .locked)
        #expect(lockedFolder == .folderLocked)
    }

    @Test(.permissionsHold) func saysWhenTheFolderAnItemGoesBackToIsGoneAndOnlyTheHelperCouldMakeIt() throws {
        let directory = try TemporaryDirectory()
        let support = try directory.directory("root/Library/Application Support")
        let trashed = try directory.file("home/.Trash/item.txt", bytes: 1)
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            )
        ) { $0 }
        let item = TrashedItem(
            originalURL: support.appending(path: "Vendor/Product/item.txt"), trashedURL: trashed, date: .now
        )
        try directory.setPermissions(0o555, of: support)
        defer { try? directory.setPermissions(0o755, of: support) }

        #expect(service.refusal(ofPuttingBack: item, canUseHelper: true) == .folderGone)
    }

    @Test(.permissionsHold) func leavesToTheHelperAWayBackOnlyRootCanLookInto() throws {
        let directory = try TemporaryDirectory()
        let vendor = try directory.directory("root/Library/Application Support/Vendor")
        try directory.directory("root/Library/Application Support/Vendor/Sub")
        let trashed = try directory.file("home/.Trash/item.txt", bytes: 1)
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            )
        ) { $0 }
        let item = TrashedItem(originalURL: vendor.appending(path: "Sub/item.txt"), trashedURL: trashed, date: .now)
        try directory.setPermissions(0o000, of: vendor)
        defer { try? directory.setPermissions(0o755, of: vendor) }

        #expect(service.refusal(ofPuttingBack: item, canUseHelper: true) == nil)
    }

    @Test(.permissionsHold) func saysWhatTheHelperWouldOfAPlaceItDoesNotServe() throws {
        let directory = try TemporaryDirectory()
        let locked = try directory.directory("home/Locked")
        let trashed = try directory.file("home/.Trash/notes.txt", bytes: 1)
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            )
        ) { $0 }
        let item = TrashedItem(originalURL: locked.appending(path: "notes.txt"), trashedURL: trashed, date: .now)
        try directory.setPermissions(0o555, of: locked)
        defer { try? directory.setPermissions(0o755, of: locked) }

        let outside = PrivilegedPathPolicy.Rejection.outsideAllowedLocations.explanation
        #expect(service.refusal(ofPuttingBack: item, canUseHelper: true) == .failed(outside))
    }

    @Test func aMoveRefusedForAnItemLockedInFinderSaysItIsLocked() async throws {
        let directory = try TemporaryDirectory()
        let locked = try directory.file("home/Library/Preferences/org.example.locked.plist")
        let path = locked.path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }
        let service = try service(in: directory)

        let result = await service.trash([locked])

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.locked])
    }

    /// Once the Trash is emptied, another item of the same name can land where an old record's item was. It is not
    /// that item: History no longer counts the old record as in the Trash, and Put Back leaves the new one where it is.
    @Test func anItemLandingLaterWhereAnotherWasIsNotTakenForIt() async throws {
        let directory = try TemporaryDirectory()
        let first = try directory.file("home/Projects/One/node_modules/left-pad/index.js")
            .deletingLastPathComponent().deletingLastPathComponent()
        let second = try directory.file("home/Projects/Two/node_modules/is-odd/index.js")
            .deletingLastPathComponent().deletingLastPathComponent()
        let service = try service(in: directory)
        let moved = try #require(await service.trash([first]).trashed.first)
        let record = RemovalRecord(batch: UUID(), item: moved, size: 10, source: "One", tool: "projects")

        // The Trash is emptied, and the next project's folder of the same name lands in the same place.
        try FileManager.default.moveItem(at: moved.trashedURL, to: directory.url.appending(path: "emptied"))
        let movedLater = try #require(await service.trash([second]).trashed.first)
        #expect(movedLater.trashedURL == moved.trashedURL, "the second folder did not land where the first had")

        #expect(!record.isStillInTrash)
        #expect(await service.restore(record.trashedItem) == .missingFromTrash)
        #expect(!FileManager.default.fileExists(atPath: first.path(percentEncoded: false)), "the other project's folder was put back here")
        #expect(FileManager.default.fileExists(atPath: movedLater.trashedURL.path(percentEncoded: false)))
    }

    /// An item is gone from the Trash only when the disk says nothing is there, or another item is. When macOS won't
    /// let Peel look, whether it is there is not known, and never read as gone, since gone records can be forgotten.
    @Test(.permissionsHold) func whatPeelCannotSeeInTheTrashIsNotKnownRatherThanGone() throws {
        let directory = try TemporaryDirectory()
        let trashed = try directory.file("home/.Trash/report.pdf")
        let item = TrashedItem(
            originalURL: directory.url.appending(path: "home/Documents/report.pdf"),
            trashedURL: trashed,
            date: .now,
            identity: TrashedItem.Identity(ofItemAt: trashed)
        )
        #expect(item.standing == .inTheTrash)

        try directory.setPermissions(0, of: "home/.Trash")
        #expect(item.standing == .notKnown)
        try directory.setPermissions(0o755, of: "home/.Trash")

        try FileManager.default.moveItem(at: trashed, to: directory.url.appending(path: "emptied"))
        #expect(item.standing == .gone)
        try directory.file("home/.Trash/report.pdf")
        #expect(item.standing == .gone, "another item in its place was taken for it")
    }

    /// Put Back asks again, of the item it holds open, whether it is the one that moved: another item could take its
    /// place between the look and the move.
    @Test func putBackLeavesAnotherItemInThePlaceItHolds() throws {
        let directory = try TemporaryDirectory()
        let original = directory.url.appending(path: "home/Projects/One/node_modules")
        try FileManager.default.createDirectory(
            at: original.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let first = try directory.directory("home/.Trash/node_modules")
        let identity = try #require(TrashedItem.Identity(ofItemAt: first))
        try FileManager.default.moveItem(at: first, to: directory.url.appending(path: "emptied"))
        try directory.directory("home/.Trash/node_modules")
        let item = TrashedItem(originalURL: original, trashedURL: first, date: .now, identity: identity)

        #expect(throws: TrashService.NotTheItemThatMoved.self) {
            try TrashService.putBack(item) { _ in nil }
        }
        #expect(!FileManager.default.fileExists(atPath: original.path(percentEncoded: false)))
    }

    /// Records come from a file any process can rewrite, so Put Back checks the folder an item really sits in.
    /// A folder that is only called `.Trash` can be a link into Messages, or sit inside iCloud Drive.
    @Test func putsNothingBackFromAFolderThatIsOnlyCalledTrash() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let secret = try directory.file("home/Library/Messages/chat.db")
        try directory.directory("drop")
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "drop/.Trash"),
            withDestinationURL: secret.deletingLastPathComponent()
        )
        let thesis = try directory.file("home/Documents/.Trash/thesis.pages")
        let nested = try directory.file("home/.Trash/folder/inside.txt")

        let planted = [
            directory.url.appending(path: "drop/.Trash/chat.db"),
            thesis,
            nested,
            directory.url.appending(path: "home/.Trash/../Documents/.Trash/thesis.pages"),
        ]
        for source in planted {
            let record = TrashedItem(originalURL: directory.url.appending(path: "out/\(source.lastPathComponent)"), trashedURL: source, date: .now)
            #expect(await service.restore(record) == .notInATrash, "\(source.path(percentEncoded: false)) was put back")
        }
        #expect(FileManager.default.fileExists(atPath: secret.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: thesis.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: nested.path(percentEncoded: false)))
    }

    /// Folders that went missing since the move are made again. Whether administrator rights are needed is
    /// decided by the nearest folder still there, not by the missing ones.
    @Test func putsAnItemBackWhenTheFoldersAroundItAreGone() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let item = try directory.file("home/code/group/project/node_modules/package.json")
        let folder = item.deletingLastPathComponent()

        let trashed = try #require(await service.trash([folder]).trashed.first)
        try FileManager.default.removeItem(at: directory.url.appending(path: "home/code/group"))

        #expect(await service.restore(trashed) == nil)
        #expect(FileManager.default.fileExists(atPath: item.path(percentEncoded: false)))
    }

    /// A relative link breaks once it is in the Trash, but it is still there and can still be put back.
    @Test func putsBackALinkThatLeadsNowhereFromTheTrash() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        try directory.file("home/Library/Application Support/Example/real.db")
        let link = directory.url.appending(path: "home/Library/Application Support/Example/current.db")
        try FileManager.default.createSymbolicLink(atPath: link.path(percentEncoded: false), withDestinationPath: "real.db")

        let trashed = try #require(await service.trash([link]).trashed.first)
        let record = RemovalRecord(batch: UUID(), item: trashed, size: 0, source: "Example", tool: "Applications")
        #expect(record.isStillInTrash)

        #expect(await service.restore(trashed) == nil)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false)) == "real.db")

        // A broken link at the original path still counts as something in the way.
        let again = try #require(await service.trash([link]).trashed.first)
        try FileManager.default.createSymbolicLink(atPath: link.path(percentEncoded: false), withDestinationPath: "gone.db")
        #expect(await service.restore(again) == .alreadyThere)
    }

    /// When macOS moves an item without saying where it went, Peel still has to find it for History. It looks by
    /// identity, not by name: macOS renames an item whose name is taken (`report.txt 20-52-06-057.txt`), and a
    /// search by name could find an older item of the same name and put that one back.
    @Test func findsAnItemMacOSDidNotNameByWhatItIs() throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("Trash")
        try directory.directory("Trash/Example.app")
        let item = try directory.directory("Example.app")
        let link = try #require(FileIdentity.Link.of(item))
        try FileManager.default.moveItem(at: item, to: trash.appending(path: "Example.app 20-52-06-057.app"))

        #expect(TrashService.item(link, in: trash)?.lastPathComponent == "Example.app 20-52-06-057.app")
        let other = try #require(FileIdentity.Link.of(try directory.directory("Other.app")))
        #expect(TrashService.item(other, in: trash) == nil)
    }

    /// Where an item goes back to is checked on disk as well: a parent folder that is a link must not lead into
    /// iCloud Drive.
    @Test func putsNothingBackThroughALinkedParent() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let cloud = try directory.directory("home/Library/Mobile Documents/com~apple~CloudDocs")
        try directory.directory("home/Library/Caches")
        try FileManager.default.createSymbolicLink(at: home.appending(path: "Library/Caches/Vendor"), withDestinationURL: cloud)
        let trashed = try directory.file("home/.Trash/x.pdf")

        let record = TrashedItem(originalURL: home.appending(path: "Library/Caches/Vendor/x.pdf"), trashedURL: trashed, date: .now)
        #expect(await service.restore(record) == .notAllowed(.protectedLocation))
        #expect(!FileManager.default.fileExists(atPath: cloud.appending(path: "x.pdf").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: trashed.path(percentEncoded: false)))
    }

    /// A service with the mover the app uses and a Trash of the test's own. `afterTheGuard` runs after the guard
    /// allows a move and before anything moves, the moment an attacker would wait for. With `hasATrash: false`,
    /// the move goes through `byName`.
    private func realService(
        in directory: borrowing TemporaryDirectory,
        afterTheGuard: @escaping @Sendable () -> Void = {},
        byName: @escaping @Sendable (URL) throws -> URL = { _ in throw CocoaError(.featureUnsupported) },
        hasATrash: Bool = true
    ) throws -> TrashService {
        let trash = try directory.directory("home/.Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let removalGuard = RemovalGuard(environment: environment)
        return TrashService(environment: environment) { url in
            try TrashService.moveToSystemTrash(
                url,
                trash: { _ in
                    guard hasATrash else { throw CocoaError(.featureUnsupported) }
                    return trash
                },
                byName: byName
            ) { pinned in
                let answer = removalGuard.refusal(of: pinned)
                afterTheGuard()
                return answer
            }
        }
    }

    /// If an item were checked by name and then moved by name, its folder could become a link into Messages in
    /// between. Peel can read files the attacker cannot, so it would move `chat.db` for them.
    @Test func movesTheItemItJudgedWhateverItsNameLeadsToByThen() async throws {
        let directory = try TemporaryDirectory()
        let secret = try directory.file("home/Library/Messages/chat.db", contents: Data("secret".utf8))
        let decoy = try directory.file("home/Library/Caches/com.evil/chat.db", contents: Data("decoy".utf8))
        let caches = directory.url.appending(path: "home/Library/Caches", directoryHint: .isDirectory)
        let service = try realService(in: directory, afterTheGuard: {
            try? FileManager.default.moveItem(at: caches.appending(path: "com.evil"), to: caches.appending(path: "com.evil.real"))
            try? FileManager.default.createSymbolicLink(
                atPath: caches.appending(path: "com.evil").path(percentEncoded: false),
                withDestinationPath: "../Messages"
            )
        })

        let result = await service.trash([decoy])

        #expect(secret.isThere, "the file in Messages was moved")
        let trashed = try #require(result.trashed.first)
        #expect(try Data(contentsOf: trashed.trashedURL) == Data("decoy".utf8))
        #expect(PathPattern.comparablePath(of: trashed.trashedURL.deletingLastPathComponent()).hasSuffix("/home/.Trash"))
    }

    /// The same race on the way back: right after the guard allows it, the folder an item returns to becomes a
    /// link into iCloud Drive. A move by name would put the file there, and it would sync to every device.
    @Test func putsAnItemBackIntoTheFolderItJudged() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let cloud = try directory.directory("home/Library/Mobile Documents/com~apple~CloudDocs")
        let caches = try directory.directory("home/Library/Caches")
        try directory.directory("home/Library/Caches/Vendor")
        let trashed = try directory.file("home/.Trash/x.pdf")
        let record = TrashedItem(originalURL: home.appending(path: "Library/Caches/Vendor/x.pdf"), trashedURL: trashed, date: .now)
        let removalGuard = RemovalGuard(
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))
        )

        try TrashService.putBack(record) { held in
            let answer = removalGuard.refusal(of: held)
            try? FileManager.default.moveItem(at: caches.appending(path: "Vendor"), to: caches.appending(path: "Vendor.real"))
            try? FileManager.default.createSymbolicLink(
                atPath: caches.appending(path: "Vendor").path(percentEncoded: false),
                withDestinationPath: cloud.path(percentEncoded: false)
            )
            return answer
        }

        #expect(!cloud.appending(path: "x.pdf").isThere, "the file was planted in iCloud Drive")
        #expect(caches.appending(path: "Vendor.real/x.pdf").isThere)
    }

    @Test func refusesADiskImageOpenRightNowAndTheFolderItIsIn() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let image = try AttachedImage(at: directory.url.appending(path: "home/Downloads/Tool/Tool.dmg"))
        let folder = image.url.deletingLastPathComponent()

        let result = await service.trash([image.url, folder])
        image.detach()

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.attachedDiskImage, .attachedDiskImage])
    }

    @Test func readsTheOpenFilesAgainWhileAMoveGoesOn() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let first = try directory.file("home/Documents/first.txt")
        let second = try directory.file("home/Documents/second.txt", bytes: 1_000_000)
        let third = try directory.file("home/Documents/third.txt")
        let reader = Mutex<Process?>(nil)
        defer { reader.withLock { $0?.terminate() } }

        let result = await service.trash([first, second, third]) { url in
            guard url == first else { return nil }
            let cat = Process()
            cat.executableURL = URL(filePath: "/bin/cat")
            cat.arguments = [second.path(percentEncoded: false)]
            cat.standardOutput = Pipe()
            try? cat.run()
            reader.withLock { $0 = cat }
            Thread.sleep(forTimeInterval: 1.05)
            return nil
        }

        #expect(result.trashed.map(\.originalURL) == [first, third])
        #expect(result.failures.map(\.reason) == [.heldOpen(by: ["cat"])])
    }

    @Test func readsTheOpenFilesAgainBeforeEachRequestToTheHelper() async throws {
        let directory = try TemporaryDirectory()
        let first = try (0..<HelperRequest.maximumItems).map {
            try directory.file("home/Library/Caches/org.example.app/\($0).cache")
        }
        let last = try directory.file("home/Library/Caches/org.example.app/last.cache", bytes: 1_000_000)
        let reader = Mutex<Process?>(nil)
        defer { reader.withLock { $0?.terminate() } }
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            moveThroughHelper: { urls in
                if !urls.contains(last) {
                    let cat = Process()
                    cat.executableURL = URL(filePath: "/bin/cat")
                    cat.arguments = [last.path(percentEncoded: false)]
                    cat.standardOutput = Pipe()
                    try? cat.run()
                    reader.withLock { $0 = cat }
                    try? await Task.sleep(for: .milliseconds(1_050))
                }
                return TrashResult(trashed: urls.map { TrashedItem(originalURL: $0, trashedURL: $0, date: .now) })
            },
            moveToTrash: { _ in throw CocoaError(.fileWriteNoPermission) }
        )

        let result = await service.trash(first + [last], usingHelperFor: Set(first + [last]))

        #expect(result.trashed.map(\.originalURL) == first)
        #expect(result.failures.map(\.reason) == [.heldOpen(by: ["cat"])])
    }

    @Test func makesNoFolderForAPutBackTheGuardRefusesOnceTheFoldersAreHeld() throws {
        let directory = try TemporaryDirectory()
        let caches = try directory.directory("home/Library/Caches")
        let trashed = try directory.file("home/.Trash/x.pdf")
        let record = TrashedItem(originalURL: caches.appending(path: "Vendor/Deep/x.pdf"), trashedURL: trashed, date: .now)
        var asked: [URL] = []

        #expect(throws: TrashService.RefusedOnceHeld.self) {
            try TrashService.putBack(record) { held in
                asked.append(held)
                return .protectedLocation
            }
        }

        #expect(asked.map { $0.path(percentEncoded: false) }.map { $0.hasSuffix("/home/Library/Caches/Vendor/Deep/x.pdf") } == [true])
        #expect(!caches.appending(path: "Vendor").isThere)
        #expect(trashed.isThere)
    }

    @Test func takesAwayTheFoldersItMadeForAPutBackThatIsThenRefused() throws {
        let directory = try TemporaryDirectory()
        let caches = try directory.directory("home/Library/Caches")
        let trashed = try directory.file("home/.Trash/x.pdf")
        let record = TrashedItem(originalURL: caches.appending(path: "Vendor/Deep/x.pdf"), trashedURL: trashed, date: .now)
        var asked = 0

        #expect(throws: TrashService.RefusedOnceHeld.self) {
            try TrashService.putBack(record) { _ in
                asked += 1
                guard asked == 2 else { return nil }
                #expect(caches.appending(path: "Vendor/Deep").isThere, "the folders were not made before the move")
                return .protectedLocation
            }
        }

        #expect(asked == 2)
        #expect(!caches.appending(path: "Vendor").isThere)
        #expect(trashed.isThere)
    }

    @Test func putsNothingBackThroughALinkPlantedWhereAFolderWasMissing() throws {
        let directory = try TemporaryDirectory()
        let caches = try directory.directory("home/Library/Caches")
        let elsewhere = try directory.directory("home/Documents/Elsewhere")
        let trashed = try directory.file("home/.Trash/x.pdf")
        let record = TrashedItem(originalURL: caches.appending(path: "Vendor/Deep/x.pdf"), trashedURL: trashed, date: .now)

        #expect(throws: POSIXError.self) {
            try TrashService.putBack(record) { _ in
                try? FileManager.default.createSymbolicLink(
                    atPath: caches.appending(path: "Vendor").path(percentEncoded: false),
                    withDestinationPath: elsewhere.path(percentEncoded: false)
                )
                return nil
            }
        }

        #expect(!elsewhere.appending(path: "Deep").isThere, "a folder was made through the link")
        #expect(trashed.isThere)
    }

    @Test func reallyMovesAFolderToTheTrashAndPutsItBack() async throws {
        let directory = try TemporaryDirectory()
        let item = try directory.file("home/Library/Caches/Example/note.txt")
        let folder = item.deletingLastPathComponent()
        let service = try realService(in: directory)

        let result = await service.trash([folder])

        #expect(result.failures.isEmpty)
        #expect(!folder.isThere)
        let trashed = try #require(result.trashed.first)
        #expect(trashed.trashedURL.appending(path: "note.txt").isThere)

        #expect(await service.restore(trashed) == nil)
        #expect(item.isThere)
        #expect(!trashed.trashedURL.isThere, "a copy was left in the Trash")
    }

    /// Nothing in the Trash is ever replaced: a second item with the same name gets a new name.
    @Test func keepsWhatIsAlreadyInTheTrashUnderThatName() async throws {
        let directory = try TemporaryDirectory()
        let service = try realService(in: directory)
        let first = try directory.file("home/Library/Caches/One/note.txt", contents: Data("first".utf8))
        let second = try directory.file("home/Library/Caches/Two/note.txt", contents: Data("second".utf8))

        let result = await service.trash([first, second])

        #expect(result.failures.isEmpty)
        #expect(result.trashed.map { $0.trashedURL.lastPathComponent } == ["note.txt", "note 2.txt"])
        #expect(try result.trashed.map { try Data(contentsOf: $0.trashedURL) } == [Data("first".utf8), Data("second".utf8)])
    }

    /// A volume where nothing was ever trashed has no Trash yet, and only `FileManager.trashItem` makes one.
    /// That call moves by name, so what it moved is checked against the item the guard judged.
    @Test func saysWhenAMoveByNameTookSomethingElse() async throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        let judged = try directory.file("home/Library/Caches/Example/note.txt")
        let other = try directory.file("home/Library/Caches/Other/note.txt")
        let honest = try realService(in: directory, byName: { url in
            let destination = trash.appending(path: "honest.txt")
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }, hasATrash: false)
        let fooled = try realService(in: directory, byName: { _ in
            let destination = trash.appending(path: "fooled.txt")
            try FileManager.default.moveItem(at: other, to: destination)
            return destination
        }, hasATrash: false)

        let wrong = await fooled.trash([judged])
        #expect(wrong.trashed.isEmpty)
        #expect(wrong.failures.map(\.url) == [judged])
        #expect(judged.isThere)

        let right = await honest.trash([judged])
        #expect(right.failures.isEmpty)
        #expect(right.trashed.map { $0.trashedURL.lastPathComponent } == ["honest.txt"])
    }

    /// The folder `PEEL_TEST_VOLUME` names, on a scratch volume whose Trash is `.Trashes/<uid>`.
    private static var scratchVolume: URL? {
        guard let path = ProcessInfo.processInfo.environment["PEEL_TEST_VOLUME"], !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// The same round trip through the Trash macOS picks for the volume. A scratch volume keeps it out of the
    /// user's own Trash.
    @Test(.enabled(if: scratchVolume != nil)) func reallyMovesAFolderToTheTrashOfAnotherVolume() async throws {
        let volume = try #require(Self.scratchVolume)
        let work = volume.appending(path: "PeelTrashRoundTrip-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let folder = work.appending(path: "home/Library/Caches/Example", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let item = folder.appending(path: "note.txt")
        try Data("note".utf8).write(to: item)
        let environment = SearchEnvironment(
            homeDirectory: work.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: work.appending(path: "root", directoryHint: .isDirectory)
        )

        let result = await TrashService(environment: environment).trash([folder])

        #expect(result.failures.isEmpty)
        let trashed = try #require(result.trashed.first)
        #expect(trashed.trashedURL.path(percentEncoded: false).contains("/.Trashes/"))
        #expect(FileManager.default.fileExists(atPath: trashed.trashedURL.path(percentEncoded: false)))

        #expect(await TrashService(environment: environment).restore(trashed) == nil)
        #expect(FileManager.default.fileExists(atPath: item.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: trashed.trashedURL.path(percentEncoded: false)), "a copy was left in the Trash")
    }

    @Test func leavesPrivilegedItemsAloneWithoutTheHelper() async throws {
        let directory = try TemporaryDirectory()
        let userItem = try directory.file("home/Library/Caches/com.example.app/cache.db").deletingLastPathComponent()
        let privilegedItem = try directory.file("root/Library/LaunchDaemons/com.example.helper.plist")

        let result = try await service(in: directory).trash(
            [userItem, privilegedItem],
            usingHelperFor: [privilegedItem]
        )

        #expect(result.trashed.map(\.originalURL) == [userItem])
        #expect(result.failures == [TrashFailure(url: privilegedItem, reason: .needsHelper)])
        #expect(FileManager.default.fileExists(atPath: privilegedItem.path(percentEncoded: false)))
    }

    @Test func refusesProtectedLocations() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Caches")
        let home = directory.url.appending(path: "home")
        let protected = [
            home,
            home.appending(path: "Library"),
            home.appending(path: "Library/Caches/"),
            URL(filePath: "/"),
            URL(filePath: "/System/Applications/Calculator.app"),
            URL(filePath: "/usr/bin/true"),
        ]

        let result = try await service(in: directory).trash(protected)

        #expect(result.trashed.isEmpty)
        let staying = TrashFailure.Reason.guarded(.staysItself), macOS = TrashFailure.Reason.guarded(.protectedLocation)
        #expect(result.failures.map(\.reason) == [staying, staying, staying, staying, macOS, macOS])
        #expect(FileManager.default.fileExists(atPath: home.appending(path: "Library/Caches").path(percentEncoded: false)))
    }

    /// A refusal says which of the guard's rules kept the item, so a plan, History and the refusal log can say why.
    @Test func saysWhichRuleKeepsEachItem() async throws {
        let directory = try TemporaryDirectory()
        let excluded = try directory.file("home/Library/Caches/org.example.Kept/cache.db").deletingLastPathComponent()
        let work = try directory.file("home/Library/Caches/org.example.Editor/LocalHistory/changes.storageData")
            .deletingLastPathComponent().deletingLastPathComponent()
        let library = try directory.file("home/Pictures/Trips/Summer.photoslibrary/database/Photos.sqlite")
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keychains = try directory.directory("home/Library/Keychains")
        let documents = try directory.directory("home/Documents")
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            ),
            exclusions: Exclusions(paths: [excluded])
        ) { $0 }

        let result = await service.trash([excluded, work, library, keychains, documents])

        #expect(result.failures.map(\.reason) == [
            .guarded(.excluded), .guarded(.holdsWorkKeptInACache), .guarded(.holdsALibrary),
            .guarded(.protectedLocation), .guarded(.staysItself),
        ])
    }

    @Test func leavesTheFolderThisVeryProgramRunsFrom() async throws {
        let directory = try TemporaryDirectory()
        let program = try #require(RunningProgram.path(of: getpid()))
        let folder = URL(filePath: program).deletingLastPathComponent()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let service = TrashService(environment: environment) { $0 }

        let result = await service.trash([folder])
        let throughTheHelper = await service.trash([folder], usingHelperFor: [folder])

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.peelRunsFromIt])
        #expect(throughTheHelper.failures.map(\.reason) == [.peelRunsFromIt])
        #expect(await service.refusalsNow(ofApps: [folder], lettingTheirProgramsRun: []) == [folder: .peelRunsFromIt])
    }

    @MainActor @Test func leavesWhatAnotherAccountRunsFromWithAReasonOfItsOwn() {
        let openFiles = OpenFiles()
        let unquittable = RunningCopies.current.filter { kill($0.identifier, 0) != 0 && errno == EPERM }
        for case let (process, bundle?) in unquittable.map({ ($0, $0.bundleURL) }) {
            let isMacOSs = RunningProgram.path(of: process.identifier).map(OpenFiles.isMacOSsOwn) ?? false
            switch openFiles.refusal(of: bundle, lettingItsProgramsRun: false) {
            case .inUseByMacOS(let names) where isMacOSs, .heldByAnotherAccount(let names) where !isMacOSs:
                #expect(names.contains(OpenFiles.name(of: process.identifier)))
            case let refusal:
                Issue.record("\(bundle.path(percentEncoded: false)) was refused as \(String(describing: refusal))")
            }
        }
    }

    @Test func leavesAFolderAnotherProcessHoldsAFileOpenIn() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let file = try directory.file("home/Library/Caches/org.example.agent/store.db")
        let folder = file.deletingLastPathComponent()
        let holder = Process()
        holder.executableURL = URL(filePath: "/bin/sleep")
        holder.arguments = ["30"]
        holder.standardInput = try FileHandle(forReadingFrom: file)
        try holder.run()
        defer { holder.terminate() }

        let held = await service.trash([folder])

        #expect(held.trashed.isEmpty)
        #expect(held.failures.map(\.reason) == [.heldOpen(by: ["sleep"])])
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))

        holder.terminate()
        holder.waitUntilExit()
        let free = await service.trash([folder])
        #expect(free.trashed.map(\.originalURL) == [folder])
    }

    /// `/var`, `/tmp`, and `/etc` are symbolic links into `/private`. A guard that knew only one spelling could
    /// be bypassed by writing the other.
    @Test func refusesTheSystemsRootsHoweverTheyAreSpelled() throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url,
            rootDirectory: directory.url.appending(path: "root")
        )
        let guardian = RemovalGuard(environment: environment)

        for path in ["/var", "/private/var", "/tmp", "/private/tmp", "/etc", "/private/etc", "/Users/Shared", "/cores",
                     "/usr/local", "/System/Library"] {
            #expect(!guardian.allowsRemoval(of: URL(filePath: path)), "the guard allows \(path)")
        }
    }

    /// A folder refused by its name is refused before anything inside it is read. Listing a folder moves an old
    /// access time and `stat` does not, so each folder's access time tells whether it was read.
    @Test func refusesByNameBeforeReadingWhatIsInside() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let keychains = home.appending(path: "Library/Keychains", directoryHint: .isDirectory)
        let folders = try [keychains] + (0..<3).map { try directory.directory("home/Library/Keychains/\($0)") }
        try directory.directory("home/Library/Keychains/0/inner")
        let guardian = RemovalGuard(
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))
        )
        let longAgo = timespec(tv_sec: 946_684_800, tv_nsec: 0)
        let accessed = { (folder: URL) in
            var info = stat()
            #expect(stat(folder.path(percentEncoded: false), &info) == 0)
            return info.st_atimespec.tv_sec
        }
        for folder in folders {
            var times = [longAgo, timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))]
            #expect(utimensat(AT_FDCWD, folder.path(percentEncoded: false), &times, 0) == 0)
        }

        #expect(!guardian.allowsRemoval(of: keychains))

        #expect(folders.map(accessed) == folders.map { _ in longAgo.tv_sec })
        #expect(ProtectedData.holdsALibrary(keychains.path(percentEncoded: false)) == .nothing)
        #expect(accessed(keychains) > longAgo.tv_sec, "listing a folder no longer moves its access time")
    }

    /// These hold work nothing can bring back. A file removed from iCloud Drive, for example, is removed from
    /// every device the user owns.
    @Test func refusesTheFoldersThatHoldWorkNothingCanBringBack() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))
        let guardian = RemovalGuard(environment: environment)

        let refused = [
            "Library/Mobile Documents/com~apple~Pages",
            "Library/Mobile Documents/iCloud~com~acme~App/Documents/plan.pages",
            "Library/CloudStorage/Dropbox",
            "Library/Keychains/login.keychain-db",
            "Library/Passes",
            "Library/Spelling/LocalDictionary",
            "Library/KeyboardServices/TextReplacements.db",
            "Library/Application Support/MobileSync/Backup",
            "Library/Mail/V10",
            "Library/Messages/chat.db",
            "Library/Containers/net.whatsapp.WhatsApp/Data/Documents/file.pdf",
            "Pictures/Photos Library.photoslibrary",
            "Pictures/Photos Library.photoslibrary/database/Photos.sqlite",
            "Music/Music/Music Library.musiclibrary",
            "Movies/TV/TV Library.tvlibrary",
            ".ssh",
            ".ssh/id_ed25519",
            ".aws/credentials",
            ".gnupg/pubring.kbx",
            ".config",
            ".cache",
            ".local",
            ".zshrc",
            ".zsh_history",
            ".gitconfig",
            ".kube",
            ".kube/config",
        ]
        for path in refused {
            #expect(!guardian.allowsRemoval(of: home.appending(path: path)), "the guard allows \(path)")
        }

        // The shared folders are protected, not what tools keep inside them.
        for path in [".config/op", ".cache/pip", ".local/share/thing", ".kube/cache/http", ".hammerspoon"] {
            #expect(guardian.allowsRemoval(of: home.appending(path: path)), "the guard refuses \(path)")
        }

        let allowed = [
            "Library/Caches/com.example.app",
            "Library/Preferences/com.example.app.plist",
            "Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches",
            "Library/Application Support/com.example.app",
            "Pictures/holiday.jpg",
        ]
        for path in allowed {
            #expect(guardian.allowsRemoval(of: home.appending(path: path)), "the guard refuses \(path)")
        }
    }

    /// A cask can name a vendor's folder while the scanner finds the app's own folder inside it. Once the
    /// vendor's folder has moved, the folder inside went with it, so it is not reported as a failure.
    @Test func whatWentWithItsFolderIsNotAFailure() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("home/Library/Application Support/Vendor")
        let inside = try directory.file("home/Library/Application Support/Vendor/App/state.db")
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            ),
            moveToTrash: { url in
                guard url.isThere else { throw CocoaError(.fileNoSuchFile) }
                let moved = directory.url.appending(path: "trash-\(url.lastPathComponent)")
                try FileManager.default.moveItem(at: url, to: moved)
                return moved
            }
        )

        let result = await service.trash([folder, inside.deletingLastPathComponent()])

        #expect(result.failures.isEmpty, "what went inside its folder was called a failure")
        #expect(result.trashed.map(\.originalURL.lastPathComponent) == ["Vendor"])
    }

    /// The helper moves items one by one and answers once, at the end. If that answer never comes (the helper
    /// was uninstalled partway, or crashed), what it did move is found in the Trash by identity. History is the
    /// only way back for an item the helper moved, so it must learn where each one went.
    @Test func whatTheHelperMovedIsFoundAgainWhenItsAnswerIsLost() throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        let moved = try directory.file("root/Library/Application Support/Vendor/moved.db")
        let stayed = try directory.file("root/Library/Application Support/Vendor/stayed.db")
        let links = [moved: FileIdentity.Link.of(moved), stayed: FileIdentity.Link.of(stayed)]
        try FileManager.default.moveItem(at: moved, to: trash.appending(path: "moved 12.34.56.db"))

        let result = PrivilegedHelper.result(for: [moved, stayed], reply: nil, links: links, trash: trash)

        #expect(result.trashed.map(\.originalURL) == [moved])
        #expect(result.trashed.first?.trashedURL.lastPathComponent == "moved 12.34.56.db")
        #expect(result.failures.map(\.url) == [stayed])
    }

    @Test(.permissionsHold) func whatTheHelperMovedIsFoundAgainInATrashPeelMayNotRead() throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        try directory.file("home/.Trash/moved.db")
        let moved = try directory.file("root/Library/Application Support/Vendor/moved.db")
        let links = [moved: FileIdentity.Link.of(moved)]
        try FileManager.default.moveItem(at: moved, to: trash.appending(path: "moved 2.db"))
        try directory.setPermissions(0o300, of: "home/.Trash")
        defer { try? directory.setPermissions(0o755, of: "home/.Trash") }

        let result = PrivilegedHelper.result(for: [moved], reply: nil, links: links, trash: trash)

        #expect(result.trashed.map(\.originalURL) == [moved])
        #expect(result.trashed.first?.trashedURL.lastPathComponent == "moved 2.db")
        #expect(result.failures.isEmpty)
    }

    @Test func anItemAlreadyGoneIsNeitherMovedNorAFailure() async throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let removalGuard = RemovalGuard(environment: environment)
        let service = TrashService(environment: environment) {
            try TrashService.moveToSystemTrash($0, refusal: removalGuard.refusal(of:))
        }
        let gone = try directory.directory("home/Library/Caches").appending(path: "org.example.gone")

        let result = await service.trash([gone])

        #expect(result.trashed.isEmpty)
        #expect(result.failures.isEmpty)
    }

    @Test func movesTheRestWhenOneItemIsAlreadyGone() async throws {
        let directory = try TemporaryDirectory()
        let service = try service(in: directory)
        let first = try directory.file("home/Library/Caches/org.example.first/first.db")
        let last = try directory.file("home/Library/Caches/org.example.last/last.db")
        let gone = directory.url.appending(path: "home/Library/Caches/org.example.gone")

        let result = await service.trash([first, gone, last])

        #expect(result.trashed.map(\.originalURL) == [first, last])
        #expect(result.failures.isEmpty)
    }

    @Test func dropsTheHelpersFailureForAnItemThatWasNeverThere() throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        let gone = directory.url.appending(path: "root/Library/Application Support/Vendor/gone.db")
        let stayed = try directory.file("root/Library/Application Support/Vendor/stayed.db")
        let links = [gone: FileIdentity.Link.of(gone), stayed: FileIdentity.Link.of(stayed)]
        let reply = HelperTrashReply(
            moved: [:],
            failed: [gone.path(percentEncoded: false): "No such file or directory", stayed.path(percentEncoded: false): "x"]
        )

        let result = PrivilegedHelper.result(for: [gone, stayed], reply: reply, links: links, trash: trash)

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.url) == [stayed])
    }

    @Test func aMakersFolderEmptiedThroughTheHelperGoesThroughIt() async throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        let root = PathPattern.comparablePath(of: try directory.directory("root"))
        let app = try directory.directory("Applications/Notes.app")
        let product = try directory.directory("root/Library/Application Support/Example/Notes")
        let own = try directory.directory("home/Library/Application Support/Example/Notes")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let move: @Sendable (URL) throws -> URL = { url in
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        let throughHelper = Mutex<[URL]>([])
        let service = TrashService(
            environment: environment,
            moveThroughHelper: { urls in
                throughHelper.withLock { $0 += urls }
                var result = TrashResult()
                for url in urls {
                    guard let trashed = try? move(url) else { continue }
                    result.trashed.append(TrashedItem(originalURL: url, trashedURL: trashed, date: .now))
                }
                return result
            },
            moveToTrash: { url in
                guard !PathComponents.isPath(PathPattern.comparablePath(of: url), inside: root) else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                return try move(url)
            }
        )
        let names = MakersFolders.names(of: [InstalledApp(url: app, bundleIdentifier: "org.example.notes", name: "Notes")])

        let result = await service.trash(
            apps: [app], thenFiles: { _ in [product, own] }, usingHelperFor: [product], lettingTheirProgramsRun: [],
            emptiedFoldersNamed: names
        )

        let makers = [product, own].map { $0.deletingLastPathComponent() }
        #expect(makers.allSatisfy { $0.isMissing })
        let emptied = Set(result.emptied.map(PathPattern.comparablePath(of:)))
        #expect(emptied == Set(makers.map(PathPattern.comparablePath(of:))))
        #expect(throughHelper.withLock { $0 } == [product, makers[0]])
        #expect(result.failures.isEmpty)
    }
}
