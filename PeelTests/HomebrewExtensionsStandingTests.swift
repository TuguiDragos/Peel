import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HomebrewExtensionsStandingTests {
    @Test func aCaskPageWaitsOnlyForAppsCarryingAnExtensionInTheirOwnFolder() {
        let plain = InstalledApp(
            url: URL(filePath: "/Applications/Plain.app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.plain", name: "Plain"
        )
        let carrying = InstalledApp(
            url: URL(filePath: "/Applications/Filter.app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.filter", name: "Filter", carriesSystemExtensions: true
        )
        let kept = RemovedElsewhere.afterItsSystemExtensions(
            CarriedSystemExtensions(names: ["Example Guard"], inAnAppInside: ["Example Guard"])
        )

        #expect(HomebrewDetailView.extensionsStanding(of: [plain], answer: nil) == .known(nil))
        #expect(HomebrewDetailView.extensionsStanding(of: [plain], answer: ([plain.url], kept)) == .known(kept))
        #expect(HomebrewDetailView.extensionsStanding(of: [carrying], answer: nil) == .waiting)
        #expect(
            HomebrewDetailView.extensionsStanding(of: [carrying], answer: ([plain.url], nil)) == .waiting,
            "an answer about other apps"
        )
    }
}
