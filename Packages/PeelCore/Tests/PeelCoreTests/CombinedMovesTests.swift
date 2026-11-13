import Foundation
@testable import PeelCore
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

    /// Writes into the disk at `disk` until it has no room left.
    private static func fill(_ disk: URL) {
        let descriptor = open(disk.appending(path: "filler").path(percentEncoded: false), O_WRONLY | O_CREAT, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        for size in [1 << 20, 1 << 12] {
            let chunk = [UInt8](repeating: 1, count: size)
            while chunk.withUnsafeBytes({ write(descriptor, $0.baseAddress, $0.count) }) > 0 {}
        }
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
}
