import Foundation
import os
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct FileSearchLibraryTests {
    private let invoice = URL(filePath: "/org.example/invoice.pdf")

    /// A library whose first search finds `invoice` and whose later ones never answer until they are stopped, with
    /// a stream that says when each search started.
    private func library() -> (FileSearchLibrary, AsyncStream<Int>.Iterator) {
        let (started, starting) = AsyncStream<Int>.makeStream()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let found = FileSearchResults(files: [
            FoundFile(
                url: invoice, size: 4_096, length: 4_096, modificationDate: .distantPast, requiresPrivileges: false
            )
        ])
        let library = FileSearchLibrary { _, _ in
            let call = calls.withLock { $0 += 1; return $0 }
            starting.yield(call)
            if call == 1 { return found }
            try? await Task.sleep(for: .seconds(3_600))
            return FileSearchResults()
        }
        return (library, started.makeAsyncIterator())
    }

    private func found(_ urls: URL...) -> FileSearchResults {
        FileSearchResults(files: urls.map {
            FoundFile(url: $0, size: 1, length: 1, modificationDate: .distantPast, requiresPrivileges: false)
        })
    }

    @Test func theKeyboardSelectsTheChosenFileAndTakesItOutAgain() async throws {
        let locked = URL(filePath: "/org.example/locked.pdf")
        let results = FileSearchResults(files: [
            FoundFile(url: invoice, size: 1, length: 1, modificationDate: .distantPast, requiresPrivileges: false),
            FoundFile(url: locked, size: 1, length: 1, modificationDate: .distantPast, requiresPrivileges: true),
        ])
        let library = FileSearchLibrary { _, _ in results }
        library.criteria.name = "report"
        await library.search()

        #expect(!library.toggleChosen(), "no row is chosen")

        library.chosen = invoice
        #expect(library.toggleChosen())
        #expect(library.isSelected(invoice))
        #expect(library.toggleChosen())
        #expect(!library.isSelected(invoice))

        library.chosen = locked
        #expect(!library.toggleChosen(), "the row's own checkbox is off")
        #expect(!library.isSelected(locked))
    }

    @Test func narrowingAnOldListLeavesTheNewOneAlone() async throws {
        let budget = URL(filePath: "/org.example/budget.pdf")
        let (first, second) = (found(invoice), found(budget))
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let landing = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)
        let narrowingHeld = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)
        let holding = OSAllocatedUnfairLock(initialState: true)
        let library = FileSearchLibrary(run: { _, _ in
            guard calls.withLock({ $0 += 1; return $0 }) > 1 else { return first }
            await withCheckedContinuation { continuation in landing.withLock { $0 = continuation } }
            return second
        }, narrowing: { files, exclusions in
            if holding.withLock({ $0 }) {
                holding.withLock { $0 = false }
                await withCheckedContinuation { continuation in narrowingHeld.withLock { $0 = continuation } }
            }
            return exclusions.keeping(files, url: \.url)
        }, exclusionsNow: { .none })
        library.criteria.name = "invoice"
        await library.search()

        library.criteria.name = "budget"
        let searching = Task { await library.search() }
        while landing.withLock({ $0 }) == nil { await Task.yield() }
        let narrowing = Task { await library.leaveOut(Exclusions(paths: [invoice])) }
        while narrowingHeld.withLock({ $0 }) == nil { await Task.yield() }
        landing.withLock { $0 }?.resume()
        while library.results?.files.map(\.url) != [budget] { await Task.yield() }
        narrowingHeld.withLock { $0 }?.resume()
        await narrowing.value
        await searching.value

        #expect(library.results?.files.map(\.url) == [budget])
        #expect(library.results?.leftOut[.excluded] == nil)
    }

    @Test func twoNarrowingsCountWhatTheyLeaveOutOnce() async throws {
        let results = found(invoice)
        let library = FileSearchLibrary(run: { _, _ in results }, exclusionsNow: { .none })
        library.criteria.name = "invoice"
        await library.search()
        let excluded = Exclusions(paths: [invoice])

        async let one: Void = library.leaveOut(excluded)
        async let other: Void = library.leaveOut(Exclusions(paths: [invoice, URL(filePath: "/org.example/other.pdf")]))
        _ = await (one, other)

        #expect(library.results?.files.isEmpty == true)
        #expect(library.results?.leftOut[.excluded] == 1)
    }

    @Test func aSearchAllLeftOutForUnreadableExclusionsRunsAgainOnceTheyAreRead() async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        var exclusions = Exclusions.unreadable
        let library = FileSearchLibrary(
            run: { _, _ in
                calls.withLock { $0 += 1 }
                return FileSearchResults()
            },
            exclusionsNow: { exclusions }
        )
        library.criteria.name = "invoice"
        await library.search()
        #expect(calls.withLock { $0 } == 1)

        exclusions = .none
        await library.leaveOut(.none)

        #expect(calls.withLock { $0 } == 2)
    }

    @Test func aSearchStoppedForOtherWordsLeavesNothingOfTheOldOnes() async {
        var (library, started) = library()
        library.criteria.name = "invoice"
        await library.search()
        library.selectedURLs = [invoice]

        library.criteria.name = "budget"
        let searching = Task { await library.search() }
        _ = await started.next(isolation: #isolation)
        _ = await started.next(isolation: #isolation)
        library.scanRun.stop()
        await searching.value

        #expect(library.results == nil)
        #expect(library.selectedURLs.isEmpty)
    }

    @Test func aRescanStoppedForTheSameWordsKeepsTheList() async {
        var (library, started) = library()
        library.criteria.name = "invoice"
        await library.search()
        library.selectedURLs = [invoice]

        let searching = Task { await library.search() }
        _ = await started.next(isolation: #isolation)
        _ = await started.next(isolation: #isolation)
        library.scanRun.stop()
        await searching.value

        #expect(library.results?.files.map(\.url) == [invoice])
        #expect(library.selectedURLs == [invoice])
    }

    @Test func clearingTheWordsKeepsWhatIsSelected() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let kept = folder.appending(path: "kept.dmg")
        let gone = folder.appending(path: "gone.dmg")
        for url in [kept, gone] { try Data(count: 16).write(to: url) }
        let records = [kept, gone].map {
            FoundFile(url: $0, size: 4_096, length: 16, modificationDate: .distantPast, requiresPrivileges: false)
        }
        let library = FileSearchLibrary { _, _ in FileSearchResults(files: records) }
        library.criteria.name = "dmg"
        await library.search()
        library.selectedURLs = [kept, gone]
        try FileManager.default.removeItem(at: gone)

        library.criteria.name = ""
        await library.search()

        #expect(library.results == nil)
        #expect(library.selectedURLs == [kept])
        #expect(Set(library.selection.outside.keys) == [kept])
        #expect(library.carriedParts.first?.sizes == [kept: 4_096])
    }

    @Test func anExclusionReachesWhatIsSelectedWithNoListOnThePage() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "file.dmg")
        try Data(count: 16).write(to: file)
        let record = FoundFile(
            url: file, size: 4_096, length: 16, modificationDate: .distantPast, requiresPrivileges: false
        )
        let library = FileSearchLibrary(run: { _, _ in FileSearchResults(files: [record]) }, exclusionsNow: { .none })
        library.criteria.name = "dmg"
        await library.search()
        library.selectedURLs = [file]
        library.criteria.name = ""
        await library.search()

        await library.leaveOut(Exclusions(paths: [file]))

        #expect(library.selectedURLs.isEmpty)
        #expect(library.selection.outside.isEmpty)
    }

    @Test func keepsSelectedWhatANewerSearchLeavesOut() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appending(path: "first.dmg")
        let second = folder.appending(path: "second.dmg")
        for url in [first, second] { try Data(count: 16).write(to: url) }
        let records = [first, second].map {
            FoundFile(url: $0, size: 4_096, length: 16, modificationDate: .distantPast, requiresPrivileges: false)
        }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let library = FileSearchLibrary { _, _ in
            let call = calls.withLock { $0 += 1; return $0 }
            return FileSearchResults(files: call == 1 ? records : [records[1]])
        }
        library.criteria.name = "dmg"
        await library.search()
        library.selectedURLs = [first, second]

        library.criteria.name = "second"
        await library.search()

        #expect(library.selectedURLs == [first, second])
        #expect(Set(library.selection.outside.keys) == [first])
        #expect(library.carriedParts.first?.sizes.keys.contains(first) == true)
        library.deselectWhatIsOutside()
        #expect(library.selectedURLs == [second])
    }
}
