import Foundation
import Testing

struct PageBindingTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: LineLengthTests.repository.appending(path: path), encoding: .utf8)
    }

    @Test func severalAppsScanAgainWhenWhatHomebrewKnowsArrives() throws {
        #expect(try source("Peel/Views/MultipleAppsView.swift").contains(".task(id: homebrew.evidenceRevision)"))
    }

    @Test func packageReceiptsLooksAgainWhenPeelComesForwardAndAfterHistory() throws {
        let list = try source("Peel/Views/Packages/PackageList.swift")

        #expect(list.contains("NSApplication.didBecomeActiveNotification"))
        #expect(list.contains(".onChange(of: history.revision)"))
        #expect(list.contains(".rescanAfterPutBack(.packages)"))
    }
}
