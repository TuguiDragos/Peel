import CoreServices
import Foundation
@testable import PeelCore
import Synchronization
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

    /// Apple says an event stream ought always to start, and to fall back to looking again from time to time when
    /// it does not. A watch that could not start still says, every so often, that the folders may have changed.
    @Test func looksAgainFromTimeToTimeWhenTheWatchCannotStart() async throws {
        let directory = try TemporaryDirectory()
        let changes = FolderWatch.changes(in: [directory.url], starting: { _ in false }, orEvery: 0.1)
        var iterator = changes.makeAsyncIterator()

        #expect(await iterator.next() != nil, "the stream ended instead of looking again")
        #expect(await iterator.next() != nil, "it looked again only once")
    }

    private static let callback = Atomic<Int>(0)
    private static let listenerIsGone = Atomic<Bool>(false)
    private static let mayReturn = DispatchSemaphore(value: 0)

    private final class Listener {
        deinit { FolderWatchTests.listenerIsGone.store(true, ordering: .sequentiallyConsistent) }
    }

    @Test func whatTheCallbackUsesLastsUntilARunningCallbackReturns() async throws {
        Self.callback.store(0, ordering: .sequentiallyConsistent)
        Self.listenerIsGone.store(false, ordering: .sequentiallyConsistent)
        let directory = try TemporaryDirectory()
        var created: FSEventStreamRef?
        do {
            let listener = Listener()
            var context = FolderWatch.context(owning: listener)
            created = withExtendedLifetime(listener) {
                FSEventStreamCreate(
                    nil,
                    { _, _, _, _, _, _ in
                        let first = FolderWatchTests.callback
                            .compareExchange(expected: 0, desired: 1, ordering: .sequentiallyConsistent).exchanged
                        guard first else { return }
                        // It runs until the test has released the stream, however long the test takes to get there.
                        FolderWatchTests.mayReturn.wait()
                        FolderWatchTests.callback.store(2, ordering: .sequentiallyConsistent)
                    },
                    &context,
                    [directory.url.path(percentEncoded: false)] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    0.05,
                    FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
                )
            }
        }
        let stream = try #require(created)
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .userInitiated))
        try #require(FSEventStreamStart(stream))
        var isReleased = false
        defer { if !isReleased { Self.mayReturn.signal() } }
        _ = try directory.file("change.txt")
        let deadline = ContinuousClock.now + Self.patience
        while Self.callback.load(ordering: .sequentiallyConsistent) == 0, .now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let running = Self.callback.load(ordering: .sequentiallyConsistent)
        try #require(running == 1, "no callback came")

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        let goneWhileRunning = Self.listenerIsGone.load(ordering: .sequentiallyConsistent)
        #expect(!goneWhileRunning, "it went while the callback was running")
        Self.mayReturn.signal()
        isReleased = true
        let released = ContinuousClock.now + Self.patience
        while !Self.listenerIsGone.load(ordering: .sequentiallyConsistent), .now < released {
            try await Task.sleep(for: .milliseconds(1))
        }
        let callback = Self.callback.load(ordering: .sequentiallyConsistent)
        let gone = Self.listenerIsGone.load(ordering: .sequentiallyConsistent)
        #expect(callback == 2)
        #expect(gone, "the stream never let it go")
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
