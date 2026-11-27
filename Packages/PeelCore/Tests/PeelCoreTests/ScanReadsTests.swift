import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct ScanReadsTests {
    /// The read holds its thread a while, as a slow disk does, so the others ask while it is under way.
    @Test func aFolderAskedAboutByManyAtOnceIsReadOnce() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("folder")
        try directory.file("folder/one")
        let read = Mutex(0)
        let reads = ScanReads(list: { url in
            read.withLock { $0 += 1 }
            usleep(20_000)
            return ScanReads.listing(of: url)
        })

        let answers = await withTaskGroup(of: ScanReads.Listing.self) { group in
            for _ in 0..<50 {
                group.addTask { await reads.listing(of: folder) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(read.withLock { $0 } == 1)
        #expect(answers.count == 50)
        #expect(answers.allSatisfy { $0 == .names(["one"]) })
    }

    @Test(.permissionsHold) func tellsAMissingFolderFromOneThatCouldNotBeListed() async throws {
        let directory = try TemporaryDirectory()
        let closed = try directory.directory("closed")
        try directory.setPermissions(0o000, of: closed)
        defer { try? directory.setPermissions(0o755, of: closed) }
        let reads = ScanReads()

        #expect(await reads.listing(of: directory.url.appending(path: "missing")) == .missing)
        #expect(await reads.listing(of: closed) == .unreadable)
    }

    @Test func readsTheNamesOfAFolderSortedAndSaysWhatIsNotOne() throws {
        let directory = try TemporaryDirectory()
        for name in ["b", "c", "a", ".hidden"] { try directory.file("folder/\(name)") }
        let folder = directory.url.appending(path: "folder", directoryHint: .isDirectory)

        #expect(ScanReads.listing(of: folder) == .names([".hidden", "a", "b", "c"]))
        #expect(ScanReads.listing(of: folder.appending(path: "a")) == .unreadable)
        #expect(ScanReads.listing(of: folder.appending(path: "a/inside")) == .missing)
    }

    @Test func readsNoFolderWithMoreEntriesThanItsLimit() throws {
        let directory = try TemporaryDirectory()
        for name in 0..<6 { try directory.file("folder/\(name)") }

        #expect(ScanReads.listing(of: directory.url.appending(path: "folder"), limit: 5) == .holdsTooMany(6))
    }

    @Test func stopsAtItsLimitOnADiskThatDoesNotTellHowManyEntriesAFolderHolds() async throws {
        let directory = try TemporaryDirectory()
        let disk = try await ScratchVolume(fileSystem: "ExFAT", mountedAt: directory.url.appending(path: "disk"))
        let folder = disk.url.appending(path: "folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in 0..<6 {
            FileManager.default.createFile(atPath: folder.appending(path: "\(name)").path(percentEncoded: false), contents: nil)
        }

        // macOS keeps a file's extended attributes beside it there, in a file of its own, so the folder holds more.
        let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()

        #expect(ScanReads.listing(of: folder, limit: entries.count - 1) == .holdsTooMany(nil))
        #expect(ScanReads.listing(of: folder, limit: entries.count) == .names(entries))
    }

    @Test func stopsAReadThatIsStoppedOrRunsPastItsBudget() async throws {
        let directory = try TemporaryDirectory()
        let disk = try await ScratchVolume(fileSystem: "ExFAT", mountedAt: directory.url.appending(path: "disk"))
        let folder = disk.url.appending(path: "folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in 0..<2_000 {
            FileManager.default.createFile(atPath: folder.appending(path: "\(name)").path(percentEncoded: false), contents: nil)
        }

        let stopped = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return ScanReads.listing(of: folder, limit: 10_000)
        }.value

        #expect(stopped == .unreadable)
        #expect(ScanReads.listing(of: folder, limit: 10_000, budget: 0) == .holdsTooMany(nil))
    }
}
