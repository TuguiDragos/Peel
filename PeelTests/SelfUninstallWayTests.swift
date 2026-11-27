import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct SelfUninstallWayTests {
    /// Finder moves only the app, so the advice to use it says what it leaves.
    @Test func theAdviceToUseFinderSaysWhatStaysBehind() {
        func words(_ block: SelfRemoval.Block) -> String {
            SelfUninstall.explanation(of: block, isAdministrator: true, helperIsRegistered: true)
        }
        for block in [SelfRemoval.Block.needsAnAdministrator, .needsItsOwner("Alex"), .leftToFinder] {
            #expect(words(block).contains("Finder"))
            #expect(words(block).contains("helper"))
            #expect(words(block).contains("login item"))
        }
        #expect(words(.needsItsOwner("Alex")).contains("the account Alex"))
        #expect(!words(.needsItsOwner("Alex")).contains("as an administrator"))
        #expect(!words(.leftToFinder).contains("Log in"))
    }

    @Test func saysThePeelCommandStaysWheneverHomebrewRemovesPeel() {
        func leaves(_ way: SelfUninstall.Way, _ status: PrivilegedHelper.Status, needs: Bool = true) -> Bool {
            SelfUninstall.leavesCommandLineTool(
                way: way, helper: status, standing: .installed, needsAnAdministrator: needs
            )
        }

        #expect(leaves(.homebrew("brew uninstall --zap --cask peel"), .enabled))
        #expect(!leaves(.removePeel, .enabled))
        #expect(leaves(.removePeel, .requiresApproval))
        #expect(!leaves(.homebrew("brew uninstall --zap --cask peel"), .enabled, needs: false))
        #expect(!SelfUninstall.leavesCommandLineTool(
            way: .homebrew("brew uninstall --zap --cask peel"), helper: .enabled, standing: .missing,
            needsAnAdministrator: true
        ))
    }

    @Test func waitsForHomebrewToSayWhetherItInstalledThisCopy() {
        let cask = HomebrewPackage(name: "peel", kind: .cask, installedVersion: "1.2.1")

        #expect(SelfUninstall.way(cask: nil, brew: "brew", homebrewKnowsItsApps: false) == .waitingForHomebrew)
        #expect(SelfUninstall.way(cask: nil, brew: "brew", homebrewKnowsItsApps: true) == .removePeel)
        #expect(SelfUninstall.way(cask: cask, brew: "brew", homebrewKnowsItsApps: false) == .homebrew("brew uninstall --zap --cask peel"))
        let odd = HomebrewPackage(name: "peel;id", kind: .cask, installedVersion: "1.2.1")
        #expect(SelfUninstall.way(cask: odd, brew: "brew", homebrewKnowsItsApps: false) == .homebrew("brew uninstall --zap --cask 'peel;id'"))
        #expect(
            SelfUninstall.way(cask: cask, brew: "/opt/brew/bin/brew", homebrewKnowsItsApps: false)
                == .homebrew("/opt/brew/bin/brew uninstall --zap --cask peel")
        )
    }

    @Test func saysWhyHomebrewDidntSayWhetherItInstalledThisCopy() {
        #expect(
            SelfUninstall.way(cask: nil, brew: "brew", homebrewKnowsItsApps: false, unanswered: .readingFailed)
                == .homebrewDidNotAnswer(.readingFailed)
        )
        #expect(
            SelfUninstall.way(cask: nil, brew: "brew", homebrewKnowsItsApps: false, unanswered: .hasToUpdate)
                == .homebrewDidNotAnswer(.hasToUpdate)
        )
        #expect(SelfUninstall.way(cask: nil, brew: "brew", homebrewKnowsItsApps: true, unanswered: nil) == .removePeel)
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
        let way = SelfUninstall.way(cask: nil, brew: "brew", homebrewKnowsItsApps: false, unanswered: .notRun)
        #expect(way == .homebrewDidNotAnswer(.notRun))
    }

    @Test func removesPeelWhereNoHomebrewPeelDoesNotRunHoldsPeel() {
        let knows = { (mayHaveInstalledPeel: Bool) in
            HomebrewLibrary.knowsWhetherItInstalledPeel(
                knowsItsOwnApps: false, isNotRun: true, mayHaveInstalledPeel: mayHaveInstalledPeel
            )
        }
        #expect(knows(false))
        #expect(!knows(true))
        let way = SelfUninstall.way(cask: nil, brew: "brew", homebrewKnowsItsApps: knows(false), unanswered: .notRun)
        #expect(way == .removePeel)
    }
}
