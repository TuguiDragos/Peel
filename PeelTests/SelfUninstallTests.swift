import Foundation
@testable import Peel
@testable import PeelCore
import Synchronization
import Testing

@MainActor
struct SelfUninstallTests {
    @Test func runsOneRemovalOfPeelAtATime() async {
        let selfUninstall = SelfUninstall { _, _ in }
        let quitGuard = QuitGuard(asksToStop: { false }, answer: { _ in })
        let runs = Mutex(0)
        let (started, start) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()

        let first = Task {
            await selfUninstall.runAlone(quitGuard: quitGuard) {
                runs.withLock { $0 += 1 }
                start.yield()
                for await _ in released { break }
            }
        }
        for await _ in started { break }
        await selfUninstall.runAlone(quitGuard: quitGuard) { runs.withLock { $0 += 1 } }
        release.yield()
        await first.value

        #expect(runs.withLock { $0 } == 1)
    }

    @Test func asksMacOSWhetherTheHelperIsRegisteredNotTheModelsLastAnswer() async {
        let helper = HelperModel.notAsking()
        let steps = SelfUninstall.steps(helper: helper, work: StandingWork(), status: { .enabled })

        #expect(!helper.isRegistered)
        #expect(await steps.helperIsRegistered())
        #expect(await steps.helperIsEnabled())
    }

    @Test func waitsForWhatPeelIsMovingFirst() async {
        let told = Mutex<[SelfUninstall.Report]>([])
        let selfUninstall = SelfUninstall { report, _ in told.withLock { $0.append(report) } }
        let quitGuard = QuitGuard(asksToStop: { false }, answer: { _ in })
        let ran = Mutex(false)

        await quitGuard.run {
            await selfUninstall.runAlone(quitGuard: quitGuard) { ran.withLock { $0 = true } }
        }

        #expect(!ran.withLock { $0 })
        #expect(told.withLock { $0.count } == 1)
    }
}

@MainActor
struct SelfUninstallAccountTests {
    @Test func waitsForAnAdministratorOnlyWhileTheHelperIsRegistered() {
        #expect(SelfUninstall.waitsForAnAdministrator(isAdministrator: false, status: .enabled))
        #expect(SelfUninstall.waitsForAnAdministrator(isAdministrator: false, status: .requiresApproval))
        #expect(!SelfUninstall.waitsForAnAdministrator(isAdministrator: false, status: .notRegistered))
        #expect(!SelfUninstall.waitsForAnAdministrator(isAdministrator: true, status: .enabled))
    }

    @Test func onAStandardAccountTheWordsNameTheButtonThatRemovesTheHelper() {
        #expect(SelfUninstall.helperGoesFirst.contains(String(localized: "Uninstall Helper")))
        #expect(SelfUninstall.helperGoesFirst.contains(String(localized: "Remove Peel")))
    }

    @Test func anAccountThatIsNotAnAdministratorIsToldOnlyTheStepsItCanTake() {
        func words(_ block: SelfRemoval.Block, isAdministrator: Bool = false, helper: Bool) -> String {
            SelfUninstall.explanation(of: block, isAdministrator: isAdministrator, helperIsRegistered: helper)
        }
        for block in [SelfRemoval.Block.needsAnAdministrator, .needsItsOwner("Alex"), .leftToFinder] {
            #expect(words(block, helper: true).contains(String(localized: "Uninstall Helper")))
            #expect(!words(block, helper: false).contains(String(localized: "Uninstall Helper")))
            for said in [words(block, helper: true), words(block, helper: false)] {
                #expect(!said.contains("Log in"))
                #expect(!said.contains("Alex"))
                #expect(said.localizedCaseInsensitiveContains("quit Peel and drag it to the Trash in Finder"))
                #expect(said.contains("stay behind"))
                #expect(said.contains(String(localized: "Open Peel at login")))
            }
        }
        for block in [SelfRemoval.Block.excluded, .readOnlyCopy] {
            #expect(words(block, helper: true) == words(block, isAdministrator: true, helper: true))
        }
    }
}
