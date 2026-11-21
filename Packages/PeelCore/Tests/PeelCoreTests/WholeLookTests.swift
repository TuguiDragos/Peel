import Darwin
import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Synchronization
import Testing

/// A folder too full for a look inside, which a move the person asked for in the app looks through whole once.
struct WholeLookTests {
    private struct Refused: Error {
        let refusal: GuardRefusal
    }

    /// `name` in the made-up home's Caches, holding a folder of more entries than a look reads.
    private func tooFull(
        in directory: borrowing TemporaryDirectory, named name: String = "net.example.client", also: [String] = []
    ) throws -> URL {
        let big = try directory.directory("home/Library/Caches/\(name)/big")
        let path = big.path(percentEncoded: false)
        for number in 0...FolderEntries.lookLimit {
            let descriptor = open(path + "/\(number)", O_CREAT | O_WRONLY | O_EXCL, 0o644)
            if descriptor >= 0 { close(descriptor) }
        }
        for inner in also { try directory.directory("home/Library/Caches/\(name)/big/\(inner)") }
        return big.deletingLastPathComponent()
    }

    /// A service whose move asks the guard again, as the move of a real item does at its rename.
    private func service(in directory: borrowing TemporaryDirectory) throws -> TrashService {
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let trash = try directory.directory("home/.Trash")
        return TrashService(environment: environment) { url in
            if let refusal = RemovalGuard(environment: environment).refusal(of: url) { throw Refused(refusal: refusal) }
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    @Test func aMoveInTheAppLooksThroughAFolderTooFullAndMovesIt() async throws {
        let directory = try TemporaryDirectory()
        let folder = try tooFull(in: directory)
        let service = try service(in: directory)

        let count = MoveCount()
        let moved = await MoveCount.$current.withValue(count) { await service.trash([folder]) }

        #expect(moved.failures.isEmpty, "\(moved.failures.map(\.reason))")
        #expect(moved.trashed.map(\.originalURL) == [folder])
        #expect(count.lookedAt > FolderEntries.lookLimit)
        #expect(!count.isLooking)
    }

    @Test func aMoveStoppedInItsFirstLookStillLooksThroughTheNext() async throws {
        let directory = try TemporaryDirectory()
        let first = try tooFull(in: directory, named: "net.example.first")
        let second = try tooFull(in: directory, named: "net.example.second")
        let service = try service(in: directory)
        let count = MoveCount()
        // Stop is pressed once the first look has begun, from a thread of its own, as the bar's click comes.
        let pressing = Thread {
            let deadline = Date.now.addingTimeInterval(60)
            while !count.isLooking, Date.now < deadline { usleep(100) }
            count.stopLooking()
        }
        pressing.start()

        let moved = await MoveCount.$current.withValue(count) { await service.trash([first, second]) }

        #expect(moved.failures.map(\.url) == [first])
        #expect(moved.failures.map(\.reason) == [.guarded(.tooManyToLookThrough)])
        #expect(moved.trashed.map(\.originalURL) == [second])
        #expect(first.isThere)
    }

    @Test func aStopStopsOnlyTheLookItWasPressedIn() async {
        let count = MoveCount()
        count.stopLooking()

        let before = await count.whileLooking { count.isStopped }
        let stopped = await count.whileLooking {
            count.addLooked(3)
            count.stopLooking()
            return count.isStopped
        }
        let after = await count.whileLooking { (count.isStopped, count.lookedAt) }

        #expect(!before)
        #expect(stopped)
        #expect(!after.0)
        #expect(after.1 == 0)
        #expect(!count.isLooking)
    }

    @Test func aLookStoppedOnceStillRemembersWhatItFindsAfter() throws {
        let directory = try TemporaryDirectory()
        let read = try directory.directory("read")
        let found = try directory.directory("found")
        let stopping = Switch()
        let look = ProtectedData.WholeLook(stoppingWhen: { stopping.isOn })

        stopping.isOn = true
        #expect(look.read(read.path(percentEncoded: false), followingLinks: false) { _, _ in true } == .tooMany)
        stopping.isOn = false
        var asked = 0
        for _ in 0..<2 {
            _ = look.remembered("probe", in: found.path(percentEncoded: false)) {
                asked += 1
                return true
            }
        }

        #expect(asked == 1)
    }

    @Test func theHelperReadsAFolderTooFullWholeOnlyUnderAWholeLook() throws {
        let directory = try TemporaryDirectory()
        let big = try directory.directory("root/Library/Caches/org.example.big/big")
        let path = big.path(percentEncoded: false)
        for number in 0...FolderEntries.lookLimit {
            let descriptor = open(path + "/\(number)", O_CREAT | O_WRONLY | O_EXCL, 0o644)
            if descriptor >= 0 { close(descriptor) }
        }
        let root = directory.url.path(percentEncoded: false)
        let policy = PrivilegedPathPolicy(
            homeDirectory: root + "home", systemLocations: [root + "root/Library/Caches"], applicationLocations: [],
            restoreLocations: [], linkLocations: [], manifestLocations: [], trustedOwner: getuid()
        )
        let item = big.deletingLastPathComponent().path(percentEncoded: false)

        #expect(policy.open(item).map(\.name) == .failure(.irreplaceable))
        let look = ProtectedData.WholeLook()
        let opened = ProtectedData.WholeLook.$current.withValue(look) { policy.open(item).map(\.name) }
        #expect(opened == .success("org.example.big"))
    }

    @Test func aFolderTooFullStaysWhenTheLookFindsWhatPeelProtects() async throws {
        let directory = try TemporaryDirectory()
        let folder = try tooFull(in: directory, also: ["Family.photoslibrary"])
        let service = try service(in: directory)

        let kept = await MoveCount.$current.withValue(MoveCount()) { await service.trash([folder]) }

        #expect(kept.trashed.isEmpty)
        #expect(kept.failures.map(\.reason) == [.guarded(.holdsALibrary)])
    }

    @Test func peelLeavesAFolderTooFullWhereItIs() async throws {
        let directory = try TemporaryDirectory()
        let folder = try tooFull(in: directory)

        let kept = try await service(in: directory).trash([folder])

        #expect(kept.trashed.isEmpty)
        #expect(kept.failures.map(\.reason) == [.guarded(.tooManyToLookThrough)])
    }
}

private final class Switch: Sendable {
    private let state = Mutex(false)

    var isOn: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
