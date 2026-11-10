import Foundation
@testable import PeelCore
import Testing

struct RemovalGuardTests {
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
