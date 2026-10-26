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
            FoundFile(url: invoice, size: 4_096, modificationDate: .distantPast, requiresPrivileges: false)
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
}
