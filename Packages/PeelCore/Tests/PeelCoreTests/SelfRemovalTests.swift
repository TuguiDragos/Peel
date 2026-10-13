import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

private actor HelperRequests {
    private(set) var sent: [URL] = []
    private(set) var ledgerMoves = 0
    private(set) var questions = 0

    func send(_ urls: [URL]) { sent += urls }
    func moveLedger() { ledgerMoves += 1 }
    func ask() { questions += 1 }
}

private actor StepLog {
    private(set) var steps: [String] = []
    private(set) var recorded: [TrashResult] = []
    private(set) var helperIsRegistered: Bool
    private let helperStays: Bool

    init(helperIsRegistered: Bool, helperStays: Bool = false) {
        self.helperIsRegistered = helperIsRegistered
        self.helperStays = helperStays
    }

    func note(_ step: String) { steps.append(step) }
    func record(_ result: TrashResult) { recorded.append(result) }

    func uninstallHelper() -> String? {
        steps.append("uninstall helper")
        helperIsRegistered = helperStays
        return helperStays ? "Not allowed." : nil
    }
}

struct SelfRemovalTests {
    private func service(
        in directory: borrowing TemporaryDirectory,
        exclusions: Exclusions = .none
    ) throws -> TrashService {
        let trash = try directory.directory("Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(environment: environment, exclusions: exclusions) { url in
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    private func paths(_ urls: [URL]) -> Set<String> {
        Set(urls.map(PathPattern.comparablePath))
    }

    private func steps(
        _ log: StepLog,
        in directory: borrowing TemporaryDirectory,
        helperMayBeChanged: Bool = true
    ) -> SelfRemoval.Steps {
        SelfRemoval.Steps(
            helperIsRegistered: { await log.helperIsRegistered },
            helperIsEnabled: { await log.helperIsRegistered },
            helperMayBeChanged: { helperMayBeChanged },
            helperAnswers: { true },
            moveLedger: { await log.note("move ledger"); return .moved },
            ledger: directory.url.appending(path: "root/var/db/org.example.helper", directoryHint: .isDirectory),
            uninstallHelper: { await log.uninstallHelper() },
            pauseWork: { await log.note("pause") },
            resumeWork: { await log.note("resume") },
            unregisterLoginItem: { await log.note("login item"); return false }
        )
    }

    @Test func removesPeelOnceItsHelperAndLoginItemAreGone() async throws {
        let directory = try TemporaryDirectory()
        let requests = HelperRequests()
        let log = StepLog(helperIsRegistered: true)
        let app = try directory.directory("home/Applications/Peel.app")
        let cache = try directory.directory("home/Library/Caches/com.example.peel")
        let folder = try directory.directory("home/Library/Application Support/Peel")
        let link = try directory.file("home/bin/peel")

        let outcome = await SelfRemoval.remove(
            [cache, app],
            links: [link],
            app: app,
            folder: folder,
            steps: steps(log, in: directory),
            using: try service(in: directory, sendingTo: requests)
        ) { await log.record($0) }

        #expect(await log.steps == ["pause", "move ledger", "uninstall helper", "login item"])
        #expect(paths(await requests.sent) == paths([link]))
        guard case .moved(let moved, let stayed, let opensAtLogin) = outcome else {
            Issue.record("Peel stayed: \(outcome)")
            return
        }
        #expect(paths([moved.originalURL]) == paths([app]))
        #expect(stayed.isEmpty)
        #expect(!opensAtLogin)
        let recorded = await log.recorded.flatMap(\.trashed).map(\.originalURL)
        #expect(paths(recorded) == paths([link, app, cache]))
        #expect(!folder.isThere)
    }

    @Test func removesPeelWithNoHelperRegistered() async throws {
        let directory = try TemporaryDirectory()
        let log = StepLog(helperIsRegistered: false)
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = try directory.directory("home/Library/Application Support/Peel")

        let outcome = await SelfRemoval.remove(
            [app], links: [], app: app, folder: folder, steps: steps(log, in: directory),
            using: try service(in: directory)
        ) { _ in }

        #expect(await log.steps == ["pause", "login item"])
        guard case .moved = outcome else {
            Issue.record("Peel stayed: \(outcome)")
            return
        }
    }

    @Test func anAccountThatCannotChangeTheHelperLeavesPeelAsItWas() async throws {
        let directory = try TemporaryDirectory()
        let log = StepLog(helperIsRegistered: true)
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = try directory.directory("home/Library/Application Support/Peel")

        let outcome = await SelfRemoval.remove(
            [app], links: [], app: app, folder: folder, steps: steps(log, in: directory, helperMayBeChanged: false),
            using: try service(in: directory)
        ) { _ in }

        #expect(outcome == .stayed(.helperIsNotThisAccounts))
        #expect(await log.steps.isEmpty)
        #expect(app.isThere)
    }

    @Test func aHelperStillRegisteredKeepsPeelWhereItWas() async throws {
        let directory = try TemporaryDirectory()
        let requests = HelperRequests()
        let log = StepLog(helperIsRegistered: true, helperStays: true)
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = try directory.directory("home/Library/Application Support/Peel")
        let link = try directory.file("home/bin/peel")

        let outcome = await SelfRemoval.remove(
            [app], links: [link], app: app, folder: folder, steps: steps(log, in: directory),
            using: try service(in: directory, sendingTo: requests)
        ) { await log.record($0) }

        #expect(outcome == .stayed(.helperStayed(reason: "Not allowed.", ledger: .moved)))
        #expect(await log.steps == ["pause", "move ledger", "uninstall helper", "resume"])
        #expect(paths(await log.recorded.flatMap(\.trashed).map(\.originalURL)) == paths([link]))
        #expect(app.isThere)
    }

    @Test(arguments: ["History unreadable", "exclusions unreadable", "exclusions not yet read"])
    func takesNoStepWhilePeelsOwnMoveWouldBeRefused(_ state: String) async throws {
        let directory = try TemporaryDirectory()
        let log = StepLog(helperIsRegistered: true)
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = try directory.directory("home/Library/Application Support/Peel")
        let history = folder.appending(path: "removals.json")
        if state == "History unreadable" {
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)
        }
        let trash = try directory.directory("Trash")
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            exclusions: state == "exclusions unreadable" ? .unreadable
                : state == "exclusions not yet read" ? .notYetRead : .none,
            journal: RemovalJournal(beside: history)
        ) { url in
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let outcome = await SelfRemoval.remove(
            [app], links: [], app: app, folder: folder, steps: steps(log, in: directory), using: service
        ) { await log.record($0) }

        let reason: TrashFailure.Reason = state == "History unreadable" ? .historyUnreadable
            : .guarded(.exclusionsNotKnown)
        #expect(outcome == .stayed(.appStayed(failures: [TrashFailure(url: app, reason: reason)], ledger: .none)))
        #expect(await log.steps.isEmpty)
        #expect(await log.recorded.isEmpty)
        #expect(app.isThere)
    }

    @Test func anAppTheMoveRefusesKeepsPeelWhereItWas() async throws {
        let directory = try TemporaryDirectory()
        let log = StepLog(helperIsRegistered: false)
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = try directory.directory("home/Library/Application Support/Peel")
        let trash = try directory.directory("Trash")
        let service = TrashService(environment: SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )) { url in
            guard url.lastPathComponent != "Peel.app" else { throw POSIXError(.EPERM) }
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let outcome = await SelfRemoval.remove(
            [app], links: [], app: app, folder: folder, steps: steps(log, in: directory), using: service
        ) { _ in }

        let refused = TrashFailure(url: app, reason: .notPermitted)
        #expect(outcome == .stayed(.appStayed(failures: [refused], ledger: .none)))
        #expect(await log.steps == ["pause", "login item", "resume"])
        #expect(folder.isThere)
    }

    private func service(
        in directory: borrowing TemporaryDirectory,
        sendingTo requests: HelperRequests
    ) throws -> TrashService {
        let trash = try directory.directory("Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(environment: environment, moveThroughHelper: { urls in
            await requests.send(urls)
            return TrashResult(trashed: urls.map {
                TrashedItem(originalURL: $0, trashedURL: trash.appending(path: $0.lastPathComponent), date: .now)
            })
        }) { url in
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    @Test func aHelperThatDoesNotAnswerIsSentNothingAndItsLinkAndLedgerStay() async throws {
        let directory = try TemporaryDirectory()
        let requests = HelperRequests()
        let link = try directory.file("home/bin/peel")
        let ledger = try directory.directory("root/var/db/org.example.helper")

        let (links, moved) = await SelfRemoval.beforeTheHelperGoes(
            links: [link],
            helperIsEnabled: true,
            using: try service(in: directory, sendingTo: requests),
            answers: { false },
            moveLedger: { await requests.moveLedger(); return .moved },
            ledger: ledger
        )

        #expect(await requests.sent.isEmpty)
        #expect(await requests.ledgerMoves == 0)
        #expect(links.trashed.isEmpty)
        #expect(links.failures == [TrashFailure(url: link, reason: .failed(PrivilegedHelper.unavailable))])
        #expect(moved == .stayed(TrashFailure(url: ledger, reason: .failed(PrivilegedHelper.unavailable))))
    }

    @Test func aHelperWaitingForApprovalIsNotAskedAndItsLedgerStays() async throws {
        let directory = try TemporaryDirectory()
        let requests = HelperRequests()
        let link = try directory.file("home/bin/peel")
        let ledger = try directory.directory("root/var/db/org.example.helper")

        let (links, moved) = await SelfRemoval.beforeTheHelperGoes(
            links: [link],
            helperIsEnabled: false,
            using: try service(in: directory, sendingTo: requests),
            answers: { await requests.ask(); return true },
            moveLedger: { await requests.moveLedger(); return .moved },
            ledger: ledger
        )

        #expect(await requests.questions == 0)
        #expect(await requests.sent.isEmpty)
        #expect(await requests.ledgerMoves == 0)
        #expect(links.trashed.isEmpty && links.failures.isEmpty)
        #expect(moved == .stayed(TrashFailure(url: ledger, reason: .failed(PrivilegedHelper.unavailable))))
    }

    @Test func withNoLedgerNoneStaysWhenTheHelperDoesNotAnswer() async throws {
        let directory = try TemporaryDirectory()
        let requests = HelperRequests()

        let (_, moved) = await SelfRemoval.beforeTheHelperGoes(
            links: [],
            helperIsEnabled: true,
            using: try service(in: directory, sendingTo: requests),
            answers: { false },
            moveLedger: { await requests.moveLedger(); return .moved },
            ledger: directory.url.appending(path: "root/var/db/org.example.helper", directoryHint: .isDirectory)
        )

        #expect(moved == .none)
        #expect(await requests.ledgerMoves == 0)
    }

    @Test func aHelperThatAnswersMovesTheLinkAndItsLedger() async throws {
        let directory = try TemporaryDirectory()
        let requests = HelperRequests()
        let link = try directory.file("home/bin/peel")
        let ledger = try directory.directory("root/var/db/org.example.helper")

        let (links, moved) = await SelfRemoval.beforeTheHelperGoes(
            links: [link],
            helperIsEnabled: true,
            using: try service(in: directory, sendingTo: requests),
            answers: { true },
            moveLedger: { await requests.moveLedger(); return .moved },
            ledger: ledger
        )

        #expect(paths(await requests.sent) == paths([link]))
        #expect(paths(links.trashed.map(\.originalURL)) == paths([link]))
        #expect(moved == .moved)
        #expect(await requests.ledgerMoves == 1)
    }

    /// History lives in the folder, so it is written first and goes with it.
    @Test func movesTheFolderLastWithTheRecordOfTheRestInside() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let cache = try directory.directory("home/Library/Caches/com.example.peel")
        let folder = try directory.directory("home/Library/Application Support/Peel")

        let result = await SelfRemoval.move(
            [cache, app],
            app: app,
            folder: folder,
            using: try service(in: directory)
        ) { result in
            try? Data("\(result.trashed.count)".utf8).write(to: folder.appending(path: "removals.json"))
        }

        #expect(paths(result.trashed.map(\.originalURL)) == paths([cache, app, folder]))
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        let moved = try #require(
            result.trashed.first {
                PathPattern.comparablePath(of: $0.originalURL) == PathPattern.comparablePath(of: folder)
            }
        )
        #expect(try String(contentsOf: moved.trashedURL.appending(path: "removals.json"), encoding: .utf8) == "2")
    }

    @Test func movesTheAppPeelRunsFrom() async throws {
        let directory = try TemporaryDirectory()
        let program = try #require(RunningProgram.path(of: getpid()))
        let app = URL(filePath: program).deletingLastPathComponent()
        let folder = try directory.directory("home/Library/Application Support/Peel")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )

        let service = TrashService(environment: environment) { $0 }

        let result = await SelfRemoval.move([app], app: app, folder: folder, using: service) { _ in }

        #expect(!result.failures.contains { $0.reason == .peelRunsFromIt })
    }

    @Test func takesItsStepsForTheAppPeelRunsFrom() async throws {
        let directory = try TemporaryDirectory()
        let log = StepLog(helperIsRegistered: true)
        let program = try #require(RunningProgram.path(of: getpid()))
        let app = URL(filePath: program).deletingLastPathComponent()
        let folder = try directory.directory("home/Library/Application Support/Peel")
        let service = TrashService(environment: SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )) { $0 }

        let outcome = await SelfRemoval.remove(
            [app], links: [], app: app, folder: folder, steps: steps(log, in: directory), using: service
        ) { _ in }

        #expect(await log.steps == ["pause", "move ledger", "uninstall helper", "login item"])
        guard case .moved = outcome else {
            Issue.record("Peel stayed: \(outcome)")
            return
        }
    }

    /// The link the helper moved before it went is written into History with the rest, as one removal.
    @Test func recordsWhatTheHelperMovedFirstWithTheRest() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = try directory.directory("home/Library/Application Support/Peel")
        let link = TrashedItem(
            originalURL: URL(filePath: "/usr/local/bin/peel"),
            trashedURL: directory.url.appending(path: "Trash/peel"),
            date: .now,
            identity: nil
        )
        var recorded: [URL] = []

        let result = await SelfRemoval.move(
            [app],
            app: app,
            folder: folder,
            movedFirst: [link],
            using: try service(in: directory)
        ) { recorded = $0.trashed.map(\.originalURL) }

        #expect(paths(recorded) == paths([link.originalURL, app]))
        #expect(paths(result.trashed.map(\.originalURL)) == paths([link.originalURL, app, folder]))
    }

    /// The Terminal settings the person's `.zshrc` and `~/.ssh/config` read stay where those lines look for them, so
    /// the shell and ssh keep them once Peel is gone. Everything else in the folder goes, History included, together
    /// in one folder named Peel, as the Trash shows the whole folder when nothing stays.
    @Test func leavesTheTerminalSettingsTheShellAndSSHRead() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = try directory.directory("home/Library/Application Support/Peel")
        try directory.file("home/Library/Application Support/Peel/Terminal/zshrc")
        try directory.file("home/Library/Application Support/Peel/Terminal/ssh_config")
        try directory.file("home/Library/Application Support/Peel/exclusions.json")
        try directory.file("home/Library/Application Support/Peel/.hidden")

        let result = await SelfRemoval.move([app], app: app, folder: folder, using: try service(in: directory)) { _ in
            try? Data("1".utf8).write(to: folder.appending(path: "removals.json"))
        }

        #expect(result.failures.isEmpty)
        #expect(!ShellFile.url(in: folder).isMissing)
        #expect(!SSHFile.url(in: folder).isMissing)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Terminal"])
        let rest = result.trashed.filter {
            PathPattern.comparablePath(of: $0.originalURL) != PathPattern.comparablePath(of: app)
        }
        #expect(rest.map(\.originalURL.lastPathComponent) == ["Peel"])
        let trashed = try #require(rest.first).trashedURL.path(percentEncoded: false)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: trashed)) == [".hidden", "exclusions.json", "removals.json"])
    }

    @Test func movesEachFileOnItsOwnWhenTheFolderCannotBeGathered() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = try directory.directory("home/Library/Application Support/Peel")
        try directory.file("home/Library/Application Support/Peel/Terminal/zshrc")
        try directory.file("home/Library/Application Support/Peel/Peel")
        try directory.file("home/Library/Application Support/Peel/exclusions.json")

        let result = await SelfRemoval.move([app], app: app, folder: folder, using: try service(in: directory)) { _ in }

        #expect(result.failures.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Terminal"])
        #expect(Set(result.trashed.map(\.originalURL.lastPathComponent)) == ["Peel.app", "Peel", "exclusions.json"])
    }

    /// When the app stays, its files and its folder stay too: Peel goes on using them.
    @Test func leavesTheFolderWhenTheAppStayed() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let cache = try directory.directory("home/Library/Caches/com.example.peel")
        let folder = try directory.directory("home/Library/Application Support/Peel")

        let result = await SelfRemoval.move(
            [cache, app],
            app: app,
            folder: folder,
            using: try service(in: directory, exclusions: Exclusions(paths: [app]))
        ) { _ in }

        #expect(paths(result.failures.map(\.url)) == paths([app]))
        #expect(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)), "a file moved although Peel stayed")
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func saysNothingOfAFolderThatWasNeverMade() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = directory.url.appending(path: "home/Library/Application Support/Peel", directoryHint: .isDirectory)

        let result = await SelfRemoval.move([app], app: app, folder: folder, using: try service(in: directory)) { _ in }

        #expect(result.failures.isEmpty)
        #expect(paths(result.trashed.map(\.originalURL)) == paths([app]))
    }

    @Test func endsOnlyTheExtensionsStillRunningFromTheMovedApp() async throws {
        let directory = try TemporaryDirectory()
        let app = "Applications/Peel.app"
        let running = try directory.runningPrograms([
            "\(app)/Contents/PlugIns/PeelFinder.appex/Contents/MacOS/PeelFinder",
            "\(app)/Contents/Helpers/peel",
            "Other.app/Contents/PlugIns/Other.appex/Contents/MacOS/Other",
        ])
        let (finder, tool, other) = (running[0], running[1], running[2])
        defer { running.forEach { $0.terminate() } }
        let moved = try directory.directory("Trash").appending(path: "Peel.app")
        try FileManager.default.moveItem(at: directory.url.appending(path: app), to: moved)

        let ended = SelfRemoval.endExtensions(runningFrom: moved)

        try #require(ended == [finder.processIdentifier])
        let endedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in ProcessEnds.of(ended) {}; return true }
            group.addTask { try? await Task.sleep(for: .seconds(60)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(endedInTime)
        #expect(kill(tool.processIdentifier, 0) == 0)
        #expect(kill(other.processIdentifier, 0) == 0)
    }
}
