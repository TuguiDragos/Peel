import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// A folder a file provider owns can hold a read in the kernel for minutes, and no answer is not an empty folder.
struct SlowReadTests {
    @Test(.fillsAFolderPastALimit) func aFolderTooFullToReadIsNotKnown() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Crowded")
        for number in 0...ScanReads.entryLimit {
            FileManager.default.createFile(atPath: folder.appending(path: "\(number)").path, contents: nil)
        }

        #expect(await SlowRead.names(in: folder) == nil)
        #expect(await SlowRead.names(in: try directory.directory("Few")) == [])
    }

    /// The read returns only after the wait has been given up on, so a busy Mac makes the test slower, never
    /// wrong.
    @Test func givesUpOnAReadThatDoesNotComeBack() async {
        let release = DispatchSemaphore(value: 0)
        let answer = await SlowRead.answer(within: 0.05) { _ in
            release.wait()
            return ["late"]
        }
        release.signal()

        #expect(answer == nil)
    }

    /// A descriptor in an answer nobody takes anymore would stay open, so such an answer goes to `discarding`.
    @Test func anAnswerThatComesTooLateIsHandedToWhatDiscardsIt() async {
        let release = DispatchSemaphore(value: 0), discarded = DispatchSemaphore(value: 0)
        let late = Mutex<[Int]>([])
        let answer = await SlowRead.answer(within: 0.05, discarding: { value in
            late.withLock { $0.append(value) }
            discarded.signal()
        }) { _ in
            release.wait()
            return 7
        }
        release.signal()
        await withCheckedContinuation { done in DispatchQueue.global().async { discarded.wait(); done.resume() } }

        #expect(answer == nil)
        #expect(late.withLock { $0 } == [7])
    }

    /// A read that works in steps stops once nobody waits for it.
    @Test func tellsAReadThatNobodyWaitsForAnymore() async {
        let started = DispatchSemaphore(value: 0)
        let stopped = Mutex(false)
        let asking = Task {
            await SlowRead.answer(within: 3_600) { isGivenUp in
                started.signal()
                let clock = ContinuousClock()
                let start = clock.now
                while !isGivenUp(), clock.now - start < .seconds(60) {
                    usleep(1_000)
                }
                stopped.withLock { $0 = isGivenUp() }
                return 0
            }
        }
        // A thread of its own cancels, since this test's own turn can come too late.
        Thread {
            started.wait()
            asking.cancel()
        }.start()
        #expect(await asking.value == nil)

        let clock = ContinuousClock()
        let start = clock.now
        while !stopped.withLock({ $0 }), clock.now - start < .seconds(10) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(stopped.withLock { $0 })
    }

    @Test func answersWhatTheReadFound() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("folder/one")
        try directory.file("folder/two")
        let file = try directory.file("plain.txt")

        let names = try #require(await SlowRead.names(in: directory.url.appending(path: "folder")))
        #expect(Set(names) == ["one", "two"])
        // Anything that is not a folder holds nothing, which is an answer.
        #expect(await SlowRead.names(in: file) == [])
        #expect(await SlowRead.names(in: directory.url.appending(path: "missing")) == [])
    }

    /// Only a folder that is not there, or is not a folder, holds nothing. Any other error leaves what it holds
    /// unknown: a link that leads back to itself stands in for the errors a disk or a file provider can give.
    @Test func aFolderThatCouldNotBeListedIsNotEmpty() async throws {
        let directory = try TemporaryDirectory()
        let loop = directory.url.appending(path: "loop")
        let path = loop.path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: "loop")

        #expect(await SlowRead.names(in: loop) == nil)
    }
}
