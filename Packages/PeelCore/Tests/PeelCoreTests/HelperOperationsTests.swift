import Darwin
import Foundation
import OSLog
@testable import PeelPrivileged
import Synchronization
import Testing

struct HelperOperationsTests {
    private func served(_ directory: borrowing TemporaryDirectory) -> PrivilegedPathPolicy {
        let root = directory.url.path(percentEncoded: false)
        return PrivilegedPathPolicy(
            homeDirectory: root + "home",
            systemLocations: [root + "root/Library/Caches"],
            applicationLocations: [],
            restoreLocations: [root + "root/Library/Caches"],
            trustedOwner: getuid()
        )
    }

    private func account(_ directory: borrowing TemporaryDirectory) -> HelperOperations.Caller {
        let home = directory.url.path(percentEncoded: false) + "home"
        return { _ in .success(HelperRequest.Caller(user: getuid(), homeDirectory: home)) }
    }

    private func ledger(_ directory: borrowing TemporaryDirectory) throws -> HelperLedger {
        try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
    }

    private func cache(_ name: String, in directory: borrowing TemporaryDirectory) throws -> String {
        try directory.file("root/Library/Caches/\(name)", contents: Data("cache".utf8)).path(percentEncoded: false)
    }

    private func logged(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let subsystem = NSPredicate(format: "subsystem == %@", HelperIdentity.helperIdentifier)
        return try store.getEntries(at: store.position(date: start), matching: subsystem)
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    }

    @Test func everyRequestLeavesALineWithItsAccountAndWhatCameOfIt() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let items = [try cache("org.example.first", in: directory), try cache("org.example.second", in: directory)]
        let long = directory.url.path(percentEncoded: false) + "root/Library/Caches/"
            + String(repeating: "x", count: 1_100)
        let policy = served(directory)
        let ledger = try ledger(directory)
        let start = Date.now

        _ = HelperOperations.moveToTrash(
            account: getuid(),
            version: HelperIdentity.protocolVersion, approval: Data(), paths: items + [long],
            caller: account(directory), policy: { _ in policy }, ledger: { ledger }
        )
        _ = HelperOperations.moveLedgerToTrash(
            account: 4_242, version: HelperIdentity.protocolVersion, caller: { _ in .failure(.notAllowed) },
            policy: { _ in policy }
        )
        _ = HelperOperations.daemonArguments(
            account: 4_243, version: HelperIdentity.protocolVersion, approval: Data(), command: "kickstart",
            label: "org.example.logged", caller: { _ in .failure(.notAuthorized) }
        )
        _ = await HelperOperations.launchctl(["kickstart", "system/org.example.logged"], for: 4_243) { _ in
            .success(Subprocess.Output(status: 3, standardOutput: Data(), standardError: Data()))
        }

        let lines = try logged(since: start)
        #expect(lines.contains("Move to the Trash for account \(getuid()): 2 moved, 1 refused"))
        #expect(lines.contains { line in
            line.hasPrefix("Move to the Trash for account \(getuid()) left ")
                && line.hasSuffix(": \(HelperRefusal.pathTooLong.rawValue)")
        })
        #expect(lines.contains(
            "Its ledger to the Trash for account 4242: refused. \(HelperRefusal.notAllowed.rawValue)"
        ))
        #expect(lines.contains(
            "launchctl kickstart org.example.logged for account 4243: refused. \(HelperRefusal.notAuthorized.rawValue)"
        ))
        #expect(lines.contains("launchctl kickstart system/org.example.logged for account 4243: exit status 3"))
    }

    @Test func aRequestWhoseTimeRanOutMovesNothingMoreAndSaysSo() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let path = try cache("org.example.cache", in: directory)
        let policy = served(directory)
        let ledger = try ledger(directory)
        let item = try policy.open(path).get()
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        let result = try #require(TrashMover.moveRecorded(
            [(path, item)], into: trash, ledger: ledger, movedBy: getuid(), until: .now - .seconds(1)
        ))

        #expect(result.moved.isEmpty)
        #expect(result.failed[path] == HelperRefusal.ranOutOfTime.rawValue)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try ledger.origin(of: item, movedBy: getuid()) == nil)
    }

    @Test func movesWhatTheHelperServesIntoTheCallersTrash() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let item = try cache("org.example.cache", in: directory)
        let policy = served(directory)
        let ledger = try ledger(directory)

        let result = HelperOperations.moveToTrash(
            account: getuid(),
            version: HelperIdentity.protocolVersion, approval: Data(), paths: [item], caller: account(directory),
            policy: { _ in policy }, ledger: { ledger }
        )

        #expect(result.failed.isEmpty)
        #expect(result.moved[item].map { FileManager.default.fileExists(atPath: $0) } == true)
        #expect(!FileManager.default.fileExists(atPath: item))
    }

    @Test(arguments: [HelperIdentity.protocolVersion - 1, HelperIdentity.protocolVersion + 1])
    func aRequestOfAnotherVersionMovesNothing(version: Int) throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let item = try cache("org.example.cache", in: directory)
        let policy = served(directory)
        let ledger = try ledger(directory)

        let result = HelperOperations.moveToTrash(
            account: getuid(),
            version: version, approval: Data(), paths: [item], caller: account(directory), policy: { _ in policy },
            ledger: { ledger }
        )

        #expect(result.moved.isEmpty)
        #expect(result.failed == [item: HelperRefusal.outOfDate.rawValue])
        #expect(FileManager.default.fileExists(atPath: item))
    }

    @Test func moreItemsThanARequestHoldsAreAllRefused() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let items = try (0...HelperRequest.maximumItems).map { try cache("org.example.cache\($0)", in: directory) }
        let policy = served(directory)
        let ledger = try ledger(directory)

        let result = HelperOperations.moveToTrash(
            account: getuid(),
            version: HelperIdentity.protocolVersion, approval: Data(), paths: items, caller: account(directory),
            policy: { _ in policy }, ledger: { ledger }
        )

        #expect(result.moved.isEmpty)
        #expect(Set(result.failed.values) == [HelperRefusal.tooManyItems.rawValue])
        #expect(items.allSatisfy { FileManager.default.fileExists(atPath: $0) })
    }

    @Test func nothingMovesWithoutALedger() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let item = try cache("org.example.cache", in: directory)
        let policy = served(directory)

        let result = HelperOperations.moveToTrash(
            account: getuid(),
            version: HelperIdentity.protocolVersion, approval: Data(), paths: [item], caller: account(directory),
            policy: { _ in policy }, ledger: { nil }
        )

        #expect(result.failed == [item: HelperRefusal.cannotKeepRecord.rawValue])
        #expect(FileManager.default.fileExists(atPath: item))
    }

    @Test func aPathTooLongIsRefusedAndTheRestMove() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let item = try cache("org.example.cache", in: directory)
        let long = directory.url.path(percentEncoded: false) + "root/Library/Caches/"
            + String(repeating: "x", count: 1_100)
        let policy = served(directory)
        let ledger = try ledger(directory)

        let result = HelperOperations.moveToTrash(
            account: getuid(),
            version: HelperIdentity.protocolVersion, approval: Data(), paths: [long, item], caller: account(directory),
            policy: { _ in policy }, ledger: { ledger }
        )

        #expect(result.failed == [long: HelperRefusal.pathTooLong.rawValue])
        #expect(Array(result.moved.keys) == [item])
    }

    @Test func anAccountTheHelperDoesNotServeGetsNothingMoved() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let item = try cache("org.example.cache", in: directory)
        let policy = served(directory)
        let ledger = try ledger(directory)

        let result = HelperOperations.moveToTrash(
            account: getuid(),
            version: HelperIdentity.protocolVersion, approval: Data("approval".utf8), paths: [item],
            caller: { _ in .failure(.notAuthorized) }, policy: { _ in policy }, ledger: { ledger }
        )

        #expect(result.failed == [item: HelperRefusal.notAuthorized.rawValue])
        #expect(FileManager.default.fileExists(atPath: item))
    }

    @Test func putsNothingBackForARequestOfAnotherVersion() throws {
        let directory = try TemporaryDirectory()
        let policy = served(directory)
        let asked = Mutex(false)

        let refusal = HelperOperations.putBack(
            account: getuid(),
            version: HelperIdentity.protocolVersion + 1, approval: Data(), from: "/tmp/in-the-trash", to: "/tmp/back",
            caller: { _ in asked.withLock { $0 = true }; return .failure(.notAllowed) }, policy: { _ in policy }
        )

        #expect(refusal == HelperRefusal.outOfDate.rawValue)
        #expect(!asked.withLock { $0 }, "the account was asked about before the version")
    }

    @Test func takesItsLedgerOnlyForTheAccountItselfWithNoApproval() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.Trash")
        let policy = served(directory)
        let home = directory.url.path(percentEncoded: false) + "home"
        let approvals = Mutex<[Data]>([])
        let moved = Mutex(false)

        let refusal = HelperOperations.moveLedgerToTrash(
            account: getuid(),
            version: HelperIdentity.protocolVersion,
            caller: { approval in
                approvals.withLock { $0.append(approval) }
                guard !approval.isEmpty else { return .failure(.notAuthorized) }
                return .success(.init(user: getuid(), homeDirectory: home))
            },
            policy: { _ in policy },
            moveFolder: { _, _ in moved.withLock { $0 = true }; return .success(nil) }
        )

        #expect(refusal == HelperRefusal.notAuthorized.rawValue)
        #expect(approvals.withLock { $0 } == [Data()])
        #expect(!moved.withLock { $0 })
    }

    @Test func aDaemonMacOSShipsNeverReachesLaunchctl() throws {
        let label = try #require(SystemDaemons.shipped.sorted().first)

        for command in ["kickstart", "bootout", "disable"] {
            let arguments = HelperOperations.daemonArguments(
                account: getuid(),
                version: HelperIdentity.protocolVersion, approval: Data(), command: command, label: label,
                caller: { _ in .success(.init(user: getuid(), homeDirectory: NSHomeDirectory())) }
            )
            #expect(arguments == .failure(.invalidRequest), "ATTACK SUCCEEDED: \(command) reached \(label)")
        }
    }

    @Test func aDaemonIsStartedOnlyFromTheOneFileThatDeclaresIt() {
        func arguments(_ command: String, files: [String]) -> Result<[String], HelperRefusal> {
            HelperOperations.daemonArguments(
                account: getuid(),
                version: HelperIdentity.protocolVersion, approval: Data(), command: command, label: "org.example.job",
                caller: { _ in .success(.init(user: getuid(), homeDirectory: NSHomeDirectory())) },
                files: { _ in files }
            )
        }

        #expect(arguments("bootstrap", files: []) == .failure(.missingConfiguration))
        #expect(arguments("bootstrap", files: ["/a.plist", "/b.plist"]) == .failure(.declaredTwice))
        #expect(arguments("bootstrap", files: ["/Library/LaunchDaemons/a.plist"])
            == .success(["bootstrap", "system", "/Library/LaunchDaemons/a.plist"]))
        #expect(arguments("restart", files: []) == .success(["kickstart", "-k", "system/org.example.job"]))
        #expect(arguments("enable", files: []) == .success(["enable", "system/org.example.job"]))
        #expect(arguments("remove", files: []) == .failure(.invalidRequest))
        #expect(arguments("kickstart", files: []) == .success(["kickstart", "system/org.example.job"]))
    }

    @Test func aDaemonCommandOfAnotherVersionOrAccountRunsNothing() {
        let other = HelperOperations.daemonArguments(
            account: getuid(),
            version: HelperIdentity.protocolVersion - 1, approval: Data(), command: "kickstart",
            label: "org.example.job",
            caller: { _ in .success(.init(user: getuid(), homeDirectory: NSHomeDirectory())) }
        )
        let refused = HelperOperations.daemonArguments(
            account: getuid(),
            version: HelperIdentity.protocolVersion, approval: Data(), command: "kickstart", label: "org.example.job",
            caller: { _ in .failure(.notAllowed) }
        )

        #expect(other == .failure(.outOfDate))
        #expect(refused == .failure(.notAllowed))
    }

    @Test func itsInterfaceTakesOnlyStringsForWhatItMoves() {
        let interface = HelperOperations.exportedInterface()
        let trash = #selector((any PeelHelperProtocol).moveItemsToTrash(version:approval:atPaths:withReply:))
        func classes(_ index: Int, ofReply: Bool) -> Set<ObjectIdentifier> {
            Set(interface.classes(for: trash, argumentIndex: index, ofReply: ofReply).compactMap {
                ($0.base as? AnyClass).map(ObjectIdentifier.init)
            })
        }

        #expect(classes(2, ofReply: false) == [ObjectIdentifier(NSArray.self), ObjectIdentifier(NSString.self)])
        for index in 0...1 {
            let strings = [ObjectIdentifier(NSDictionary.self), ObjectIdentifier(NSString.self)]
            #expect(classes(index, ofReply: true) == Set(strings))
        }
    }
}
