import Foundation
import Testing

struct SeveralAppsPageTests {
    @Test func scansAgainWhenWhatHomebrewKnowsArrives() throws {
        let view = LineLengthTests.repository.appending(path: "Peel/Views/MultipleAppsView.swift")
        let source = try String(contentsOf: view, encoding: .utf8)

        #expect(source.contains(".task(id: homebrew.evidenceRevision)"))
    }
}
