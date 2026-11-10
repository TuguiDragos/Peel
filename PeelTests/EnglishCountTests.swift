import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct EnglishCountTests {
    /// `peel` prints a History entry's name as written, so a count past three is English in any language Peel shows,
    /// which a test run in a language with three plural forms proves.
    @Test func aCountHistoryKeepsIsEnglishInEveryLanguage() {
        let casks = (1...5).map { HomebrewPackage(name: "example\($0)", kind: .cask) }
        let receipts = (1...5).map {
            PackageReceipt(
                identifier: "org.example.pkg\($0)", version: nil, installDate: nil, volume: URL(filePath: "/"), items: []
            )
        }
        let apps = (1...5).map {
            InstalledApp(url: URL(filePath: "/Applications/Example \($0).app"), bundleIdentifier: nil, name: "Example \($0)")
        }

        #expect(BulkRemovalPlan(apps: apps).part(naming: apps).source == "5 apps")
        #expect(HomebrewLibrary.source(of: casks, after: TrashResult()).source == "5 casks")
        #expect(PackageLibrary.source(of: receipts).source == "5 receipts")
    }
}
