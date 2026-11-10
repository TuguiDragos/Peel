import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct RemovalGuardTests {
    /// The protected trees sit in the same few folders, so each folder above them is read once.
    @Test func protectedObjectsReadEachPathOnce() throws {
        let directory = try TemporaryDirectory()
        let shared = try directory.directory("shared")
        let trees = try (0..<100).map { try directory.directory("shared/tree\($0)").path(percentEncoded: false) }
        let reads = Mutex<[String: Int]>([:])

        _ = ProtectedObjects(trees: trees, folders: trees + trees) { path, followingLinks in
            reads.withLock { $0["\(path) \(followingLinks)", default: 0] += 1 }
            return ProtectedObjects.object(at: path, followingLinks: followingLinks)
        }

        #expect(reads.withLock { $0.filter { $0.value > 1 }.keys.sorted() } == [])
        #expect(reads.withLock { $0["\(PathPattern.comparablePath(of: shared)) false"] } == 1)
    }

    /// Making a service is what a page does on the main thread when a move is confirmed, so the guard waits for its
    /// first use, which the moves make away from it.
    @Test func aServiceMakesItsGuardOnlyOnceItIsUsed() throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: try directory.directory("home"), rootDirectory: try directory.directory("root")
        )
        let made = Mutex(0)
        let service = TrashService(environment: environment, makingTheGuard: {
            made.withLock { $0 += 1 }
            return RemovalGuard(environment: environment)
        }) { $0 }

        #expect(service.knowsTheExclusions)
        #expect(service.refusalOfEveryMove == nil)
        #expect(made.withLock { $0 } == 0)
        _ = service.refusal(of: directory.url.appending(path: "home/file"))
        _ = service.refusal(of: directory.url.appending(path: "home/other"))
        #expect(made.withLock { $0 } == 1)
    }

    /// The footprint covers the whole process, and suites running in parallel would add their own allocations to it,
    /// so the check runs in a process of its own.
    @Test func theGuardLetsGoOfWhatEachQuestionMade() async {
        await #expect(processExitsWith: .success, "5,000 questions held what they made until their caller let go") {
            if try RemovalGuardTests.heldByQuestions(5_000) >= 5_000 * 2_048 {
                exit(EXIT_FAILURE)
            }
        }
    }

    /// How much more memory the process holds after the guard is asked about `count` files, before the pool of the
    /// loop that asked drains.
    private static func heldByQuestions(_ count: Int) throws -> UInt64 {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("home/Downloads/Copies")
        let files = (0..<count).map { folder.appending(path: "copy-\($0).txt") }
        for file in files {
            FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: Data("x".utf8))
        }
        let guardian = RemovalGuard(environment: SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        ))
        let before = FileSizeTests.footprint()
        var held: UInt64 = 0
        autoreleasepool {
            for file in files {
                _ = guardian.refusal(of: file)
            }
            let after = FileSizeTests.footprint()
            held = after > before ? after - before : 0
        }
        return held
    }
}
