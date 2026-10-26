import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HomebrewUpdateFirstTests {
    @Test func asksForAnUpdateAboveListsReadBeforeTheDefinitionsWent() {
        let read = [HomebrewPackage(name: "wget", kind: .formula, installedVersion: "1.25")]

        #expect(HomebrewList.asksToUpdateAboveTheLists(needsDefinitions: true, packages: read))
        #expect(!HomebrewList.asksToUpdateAboveTheLists(needsDefinitions: true, packages: []))
        #expect(!HomebrewList.asksToUpdateAboveTheLists(needsDefinitions: false, packages: read))
    }
}
