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
}
