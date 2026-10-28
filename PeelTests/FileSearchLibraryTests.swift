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
