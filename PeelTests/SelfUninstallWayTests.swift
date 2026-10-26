import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct SelfUninstallWayTests {
    @Test func waitsForHomebrewToSayWhetherItInstalledThisCopy() {
        let cask = HomebrewPackage(name: "peel", kind: .cask, installedVersion: "1.2.1")

        #expect(SelfUninstall.way(cask: nil, homebrewKnowsItsApps: false) == .waitingForHomebrew)
        #expect(SelfUninstall.way(cask: nil, homebrewKnowsItsApps: true) == .removePeel)
        #expect(SelfUninstall.way(cask: cask, homebrewKnowsItsApps: false) == .homebrew("brew uninstall --zap --cask peel"))
    }
}
