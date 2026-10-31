import Foundation
@testable import Peel
@testable import PeelCore
import Synchronization
import Testing

@MainActor
struct SpaceLibraryTests {
    @Test func readsTheDiskAgainWithoutScanning() async {
        let space = SpaceLibrary()

        await space.readDisk()

        #expect(space.disk.map { $0.storage.total > 0 } == true)
        #expect(space.report == nil)
    }

    @Test func aPlanThatStartedEarlierAndEndedLaterIsDropped() async throws {
        let older = URL(filePath: "/Users/x/Library/Caches/org.example.moved")
        let newer = URL(filePath: "/Users/x/Library/Caches/org.example.left")
        let waiting = Mutex<[CheckedContinuation<SpaceRemoval.Plan, Never>]>([])
        let space = SpaceLibrary(makingPlans: { _, _, _ in
            await withCheckedContinuation { continuation in waiting.withLock { $0.append(continuation) } }
        })
        let item = SpaceItem(
            id: "caches", category: .library, urls: [URL(filePath: "/Users/x/Library/Caches")],
            size: SizeTotal(known: 0, isComplete: true), handling: .trash
        )
        func plan(_ url: URL) -> SpaceRemoval.Plan {
            SpaceRemoval.Plan(removable: [url], inUse: [], leftToDeveloper: [], sizes: [url: 1])
        }

        let first = Task { await space.plan(item) }
        while waiting.withLock({ $0.count }) < 1 { await Task.yield() }
        let second = Task { await space.plan(item) }
        while waiting.withLock({ $0.count }) < 2 { await Task.yield() }
        let (one, two) = waiting.withLock { ($0[0], $0[1]) }

        two.resume(returning: plan(newer))
        await second.value
        one.resume(returning: plan(older))
        await first.value

        #expect(space.plans["caches"]?.removable == [newer])
    }
}
