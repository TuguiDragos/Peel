import Foundation
@testable import Peel
import PeelCore
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
        #expect(SelfUninstall.waitsForAnAdministrator(standing: .notThisAccount, status: .enabled))
        #expect(SelfUninstall.waitsForAnAdministrator(standing: .notThisAccount, status: .requiresApproval))
        #expect(!SelfUninstall.waitsForAnAdministrator(standing: .notThisAccount, status: .notRegistered))
        #expect(!SelfUninstall.waitsForAnAdministrator(standing: .ready, status: .enabled))
    }
}
