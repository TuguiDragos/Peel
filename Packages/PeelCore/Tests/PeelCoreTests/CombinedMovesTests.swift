import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Synchronization
import Testing

/// The moves that go wrong one way on top of another: a disk that fills, a process that dies, a disk that goes away.
struct CombinedMovesTests {
    private func environment(in directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
    }

    /// A service that moves into a Trash folder of the test's own, with History and its journal at `history`.
    private func service(in directory: borrowing TemporaryDirectory, history: URL) throws -> TrashService {
        let trash = try directory.directory("home/.Trash")
        let environment = environment(in: directory)
        let removalGuard = RemovalGuard(environment: environment)
        return TrashService(environment: environment, journal: RemovalJournal(beside: history)) { url in
            try TrashService.moveToSystemTrash(url, trash: { _ in trash }, refusal: removalGuard.refusal(of:))
        }
    }

    /// Writes into the disk at `disk` until it has no room left, then once more after closing the file, which can give
    /// back room it held, and records an issue when a write stops for any other reason, since the test would then prove
    /// nothing.
    private static func fill(_ disk: URL) {
        let path = disk.appending(path: "filler").path(percentEncoded: false)
        for flags in [O_WRONLY | O_CREAT, O_WRONLY | O_APPEND] {
            let descriptor = open(path, flags, 0o600)
            guard descriptor >= 0 else {
                Issue.record("the filler couldn't be opened: \(String(cString: strerror(errno)))")
                return
            }
            defer { close(descriptor) }
            for size in [1 << 20, 1 << 12, 1 << 9] {
                let chunk = [UInt8](repeating: 1, count: size)
                while true {
                    let written = chunk.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
                    if written > 0 || written < 0 && errno == EINTR { continue }
                    if written < 0, errno == ENOSPC { break }
                    Issue.record("filling stopped: \(written < 0 ? String(cString: strerror(errno)) : "0 bytes")")
                    return
                }
            }
        }
    }

    /// Whether a new file can still be made on the disk at `disk`, as a journal's first line makes one.
    private static func takesANewFile(_ disk: URL) -> Bool {
        let descriptor = open(disk.appending(path: "probe").path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    @Test func aDiskWithNoRoomForHistoryMovesNothingAndSaysSo() async throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(
            fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk"), size: "256m"
        )
        let history = disk.url.appending(path: "Peel/removals.json")
        try FileManager.default.createDirectory(
            at: history.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        Self.fill(disk.url)
        try #require(!Self.takesANewFile(disk.url), "the disk took a new file after it was filled")
        let files = try (1...2).map { try directory.file("home/Library/Caches/org.example.full/\($0).txt") }
        let service = try service(in: directory, history: history)
        let folder = RemovalJournal(beside: history).url.deletingLastPathComponent()

        let result = await service.trash(files)

        #expect(result.trashed.isEmpty)
        let full = TrashFailure.Reason.historyCannotBeWritten(.noRoomLeft(folder))
        #expect(result.failures.map(\.reason) == [full, full])
        #expect(files.allSatisfy { !$0.isMissing })
        withExtendedLifetime(disk) {}
    }

    @Test func aDiskThatFillsBetweenTwoItemsKeepsWhatMovedWrittenDown() async throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(
            fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk"), size: "256m"
        )
        let place = disk.url
        let history = place.appending(path: "Peel/removals.json")
        let files = try (1...3).map { try directory.file("home/Library/Caches/org.example.filling/\($0).txt") }
        let service = try service(in: directory, history: history)
        let journal = RemovalJournal(beside: history)
        let asked = Mutex(0)

        let result = await service.trash(files, refusing: { _ in
            if asked.withLock({ $0 += 1; return $0 }) == 2 { Self.fill(place) }
            return nil
        })

        let moved = Set(result.trashed.map(\.originalURL))
        #expect(moved.contains(files[0]))
        #expect(moved.isSubset(of: Set(journal.entries().map(\.item.originalURL))), "an item moved with no line")
        #expect(files.filter { !moved.contains($0) }.allSatisfy { !$0.isMissing })
        #expect(result.trashed.allSatisfy { !$0.trashedURL.isMissing })
        let full = TrashFailure.Reason.historyCannotBeWritten(.noRoomLeft(journal.url.deletingLastPathComponent()))
        #expect(result.failures.allSatisfy { $0.reason == full })
        withExtendedLifetime(disk) {}
    }

    /// The writer a process killed halfway through a move leaves on its lines: one that has ended.
    private func endedProcess() throws -> RemovalJournal.Writer {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return RemovalJournal.Writer(pid: process.processIdentifier, started: 1)
    }

    @Test func aRemovalKilledHalfwayOnAnExFATDiskIsInHistoryAndGoesBackFromThatDisksTrash() async throws {
        let directory = try TemporaryDirectory()
        let place = directory.url.appending(path: "Disk", directoryHint: .isDirectory)
        let disk = try ScratchVolume(fileSystem: "ExFAT", mountedAt: place)
        let files = try (1...3).map { number -> URL in
            let file = place.appending(path: "org.example.cut/\(number).txt")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("\(number)".utf8).write(to: file)
            return file
        }
        let history = directory.url.appending(path: "Peel/removals.json")
        let environment = environment(in: directory)
        let removalGuard = RemovalGuard(environment: environment)
        let killed = RemovalJournal(beside: history, writtenBy: try endedProcess())
        let service = TrashService(environment: environment, journal: killed) { url in
            try TrashService.moveToSystemTrash(url, refusal: removalGuard.refusal(of:))
        }

        // The process dies once two items have moved: the third never moves, and nothing reaches History.
        let moved = await service.trash(Array(files.prefix(2)))
        try #require(moved.trashed.count == 2)
        let records = try #require(await RemovalLog(url: history).load().records)

        #expect(Set(records.map(\.originalURL)) == Set(files.prefix(2)))
        #expect(Set(records.map(\.batch)).count == 1)
        #expect(records.allSatisfy { $0.sourceKey == "interrupted" })
        let trash = PathPattern.comparablePath(of: place.appending(path: ".Trashes/\(getuid())"))
        #expect(records.allSatisfy {
            PathPattern.comparablePath(of: $0.trashedURL.deletingLastPathComponent()) == trash
        })
        #expect(killed.entries().isEmpty)
        #expect(!files[2].isMissing)

        let restored = await service.restore(records.map(\.trashedItem))

        #expect(restored.failures.allSatisfy { $0 == nil })
        #expect(try files.map { try String(contentsOf: $0, encoding: .utf8) } == ["1", "2", "3"])
        withExtendedLifetime(disk) {}
    }

    @Test func whatAMoveCutShortLeftInStagingGoesToTheTrashAndBackAsItWas() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.path(percentEncoded: false)
        try directory.directory("home/.Trash")
        let original = try directory.file(
            "root/Library/Caches/org.example.staged/cache.db", contents: Data("cache".utf8)
        ).deletingLastPathComponent().path(percentEncoded: false)
        let policy = PrivilegedPathPolicy(
            homeDirectory: root + "home",
            systemLocations: [root + "root/Library/Caches"],
            applicationLocations: [],
            restoreLocations: [root + "root/Library/Caches"],
            trustedOwner: getuid()
        )
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        var before = stat()
        try #require(lstat(original, &before) == 0)
        let item = try policy.open(original).get()

        // The helper wrote the item down and took it into Staging, then stopped before it reached the Trash.
        try #require(ledger.record([item], movedBy: getuid()))
        let staging = try directory.directory("private/Staging")
        try directory.setPermissions(0o700, of: "private/Staging")
        let staged = staging.appending(path: "\(getuid()).\(UUID().uuidString).\(item.name)")
        try #require(rename(original, staged.path(percentEncoded: false)) == 0)

        HelperLedger.recoverStaged(in: root + "private") { $0 == getuid() ? root + "home" : nil }

        let trashed = root + "home/.Trash/" + item.name
        #expect(FileManager.default.fileExists(atPath: trashed))
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path(percentEncoded: false)).isEmpty)
        #expect(HelperPutBack.run(trashed, to: original, for: getuid(), policy: policy, ledger: { ledger }) == nil)

        var after = stat()
        try #require(lstat(original, &after) == 0)
        #expect(after.st_ino == before.st_ino && after.st_uid == before.st_uid && after.st_mode == before.st_mode)
        #expect(try String(contentsOfFile: original + "/cache.db", encoding: .utf8) == "cache")
        #expect(try ledger.origin(of: try policy.open(original).get(), movedBy: getuid()) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root + "home/.Trash").isEmpty)
    }

    @Test func aDiskTakenAwayHalfwayKeepsWhatMovedWrittenDownAndPutsItBackWhereverItComesBack() async throws {
        let directory = try TemporaryDirectory()
        let place = directory.url.appending(path: "Disk", directoryHint: .isDirectory)
        let disk = try ScratchVolume(fileSystem: "MS-DOS FAT32", mountedAt: place)
        let files = try (1...3).map { number -> URL in
            let file = place.appending(path: "org.example.away/\(number).txt")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("\(number)".utf8).write(to: file)
            return file
        }
        let history = directory.url.appending(path: "Peel/removals.json")
        let environment = environment(in: directory)
        let removalGuard = RemovalGuard(environment: environment)
        let service = TrashService(
            environment: environment, journal: RemovalJournal(beside: history, writtenBy: try endedProcess())
        ) { url in
            try TrashService.moveToSystemTrash(url, refusal: removalGuard.refusal(of:))
        }
        let mountPoint = place.path(percentEncoded: false)
        let asked = Mutex(0)

        let result = await service.trash(files, refusing: { _ in
            if asked.withLock({ $0 += 1; return $0 }) == 2 {
                _ = try? DiskImageTool.eject(mountPoint)
            }
            return nil
        })

        #expect(result.trashed.map(\.originalURL) == [files[0]])
        let records = try #require(await RemovalLog(url: history).load().records)
        #expect(records.map(\.originalURL) == [files[0]])
        #expect(records.allSatisfy { $0.disk != nil })
        #expect(RemovalStanding(records).away == Set(records.map(\.id)))

        let elsewhere = directory.url.appending(path: "Elsewhere", directoryHint: .isDirectory)
        try disk.attach(at: elsewhere)
        let located = try #require(records.first).located(on: .now())

        #expect(await service.restore(located.trashedItem) == nil)
        #expect(try (1...3).map { number in
            try String(contentsOf: elsewhere.appending(path: "org.example.away/\(number).txt"), encoding: .utf8)
        } == ["1", "2", "3"])
        withExtendedLifetime(disk) {}
    }
}
