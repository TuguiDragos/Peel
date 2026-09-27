import Foundation
@testable import PeelCore
import Testing

struct FolderWatchTests {
    /// Each wait returns at the first change, so only a broken watch waits this long; a busy Mac can hold FSEvents
    /// back for many seconds.
    private static let patience = Duration.seconds(60)

    /// The stream keeps the last change, so one that lands before anyone reads is not lost.
    @Test func saysWhenSomethingAppearsInAFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("watched")
        let folder = directory.url.appending(path: "watched", directoryHint: .isDirectory)
        let changes = FolderWatch.changes(in: [folder])

        try FileManager.default.createDirectory(at: folder.appending(path: "New.app"), withIntermediateDirectories: false)

        #expect(await firstChange(of: changes, within: Self.patience), "no change arrived")
    }

    @Test func saysWhenSomethingLeavesAFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("watched/Old.app")
        let folder = directory.url.appending(path: "watched", directoryHint: .isDirectory)
        let changes = FolderWatch.changes(in: [folder])

        try FileManager.default.removeItem(at: folder.appending(path: "Old.app"))

        #expect(await firstChange(of: changes, within: Self.patience), "no change arrived")
    }

    /// The control: without this, a watcher that reported constantly would pass the tests above.
    @Test func staysSilentWhileNothingHappens() async throws {
        let directory = try TemporaryDirectory()
        // The fixture's own change is heard first, so the watch under test cannot take it for its first.
        let setup = FolderWatch.changes(in: [directory.url])
        try directory.directory("watched/Untouched.app")
        try #require(await firstChange(of: setup, within: Self.patience), "the fixture's own change was never heard")
        let folder = directory.url.appending(path: "watched", directoryHint: .isDirectory)
        let changes = FolderWatch.changes(in: [folder])

        #expect(await firstChange(of: changes, within: .seconds(2)) == false, "a change was reported out of nothing")
    }

    /// Adobe and Setapp keep their apps a folder or two down (`/Applications/Setapp/Foo.app`), where the
    /// catalog finds them. A watch on the top folder alone would miss an update to one of those.
    @Test func hearsAChangeTwoFoldersDown() async throws {
        let directory = try TemporaryDirectory()
        let vendor = try directory.directory("watched/Vendor")
        let changes = FolderWatch.changes(in: [directory.url.appending(path: "watched", directoryHint: .isDirectory)])

        try FileManager.default.createDirectory(at: vendor.appending(path: "New.app/Contents"), withIntermediateDirectories: true)

        #expect(await firstChange(of: changes, within: Self.patience), "no change arrived")
    }

    /// `~/Applications` does not exist on a new Mac, and the first app put into it must still be noticed.
    @Test func hearsOfAFolderThatIsMadeLater() async throws {
        let directory = try TemporaryDirectory()
        let later = directory.url.appending(path: "Applications", directoryHint: .isDirectory)
        let changes = FolderWatch.changes(in: [later])

        try FileManager.default.createDirectory(at: later.appending(path: "New.app"), withIntermediateDirectories: true)

        #expect(await firstChange(of: changes, within: Self.patience), "no change arrived")
    }

    private func firstChange(of changes: AsyncStream<Void>, within limit: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = changes.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
