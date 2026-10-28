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

    @Test func saysWhyHomebrewDidntSayWhetherItInstalledThisCopy() {
        #expect(
            SelfUninstall.way(cask: nil, homebrewKnowsItsApps: false, unanswered: .readingFailed)
                == .homebrewDidNotAnswer(.readingFailed)
        )
        #expect(
            SelfUninstall.way(cask: nil, homebrewKnowsItsApps: false, unanswered: .hasToUpdate)
                == .homebrewDidNotAnswer(.hasToUpdate)
        )
        #expect(SelfUninstall.way(cask: nil, homebrewKnowsItsApps: true, unanswered: nil) == .removePeel)
        #expect(SelfUninstall.Way.homebrewDidNotAnswer(.readingFailed).waitsForHomebrew)
        #expect(!SelfUninstall.Way.removePeel.waitsForHomebrew)
    }

    @Test func waitsWhileThereIsAHomebrewPeelDoesNotRun() {
        #expect(!HomebrewLibrary.knowsItsOwnApps(isInstalled: false, hasAnswered: false, isNotRun: true))
        #expect(HomebrewLibrary.knowsItsOwnApps(isInstalled: false, hasAnswered: false, isNotRun: false))
        #expect(
            HomebrewLibrary.unanswered(
                isInstalled: false, hasAnswered: false, couldNotRead: false, needsDefinitions: false, isNotRun: true
            ) == .notRun
        )
        let way = SelfUninstall.way(cask: nil, homebrewKnowsItsApps: false, unanswered: .notRun)
        #expect(way == .homebrewDidNotAnswer(.notRun))
    }
}
