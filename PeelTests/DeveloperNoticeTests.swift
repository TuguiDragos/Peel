import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct DeveloperNoticeTests {
    @Test func theNoticeComesWithThePlanBeforeItsSizesAreMeasured() {
        let caches = URL(filePath: "/Users/someone/Library/Caches", directoryHint: .isDirectory)
        var plan = SpaceRemoval.Plan(
            removable: [caches.appending(path: "org.example.app")], inUse: [],
            leftToDeveloper: [caches.appending(path: "Homebrew")], sizes: [:]
        )

        #expect(SpaceDetailView.showsDeveloperNotice(for: plan))
        plan.developerSizes = [caches.appending(path: "Homebrew"): 1]
        #expect(SpaceDetailView.showsDeveloperNotice(for: plan))
        let nothingLeft = SpaceRemoval.Plan(removable: [], inUse: [], leftToDeveloper: [], sizes: [:])
        #expect(!SpaceDetailView.showsDeveloperNotice(for: nothingLeft))
    }
}
