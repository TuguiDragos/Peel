import Foundation
@testable import Peel
import PeelCore
import Synchronization
import Testing

@MainActor
struct HomeAppManagementTests {
    @Test func aRefusalGivesWayOnceSystemSettingsHasBeenInFront() throws {
        let madeUp = try MadeUpDefaults()
        defer { madeUp.forget() }
        let frontmost = FrontmostApp(observing: false)
        let home = HomeModel(helper: HelperModel(), defaults: madeUp.defaults, frontmost: frontmost)

        frontmost.note("com.apple.systempreferences")
        frontmost.note("org.example.other")
        home.record(appManagement: .missing)
        home.followSystemSettings()
        #expect(home.state(of: .appManagement) == .missing)
        #expect(home.missingRequired.contains(.appManagement))

        frontmost.note("com.apple.systempreferences")
        frontmost.note("com.tuguidragos.Peel")
        home.followSystemSettings()
        #expect(home.state(of: .appManagement) == .pending)
        #expect(!home.missingRequired.contains(.appManagement))
        #expect(home.waitingRequired.contains(.appManagement))
        #expect(home.appManagementAwaitsARemoval)

        home.record(appManagement: .granted)
        #expect(home.state(of: .appManagement) == .on)
        #expect(!home.waitingRequired.contains(.appManagement))
        #expect(!home.appManagementAwaitsARemoval)
    }

    @Test func aRefusalFromAnEarlierLaunchWaitsForTheNextRemoval() throws {
        let madeUp = try MadeUpDefaults()
        defer { madeUp.forget() }
        let frontmost = FrontmostApp(observing: false)
        HomeModel(helper: HelperModel(), defaults: madeUp.defaults, frontmost: frontmost)
            .record(appManagement: .missing)

        let home = HomeModel(helper: HelperModel(), defaults: madeUp.defaults, frontmost: frontmost)

        #expect(!home.missingRequired.contains(.appManagement))
        #expect(home.waitingRequired.contains(.appManagement))
    }

    @Test func saysWhenPeelLearnsItsAnswer() async throws {
        let madeUp = try MadeUpDefaults()
        defer { madeUp.forget() }
        let frontmost = FrontmostApp(observing: false)
        let home = HomeModel(helper: HelperModel(), defaults: madeUp.defaults, frontmost: frontmost)
        await home.refresh()
        #expect(home.status(of: .appManagement) == "Known once Peel moves another developer’s app")

        frontmost.note("com.apple.systempreferences")
        frontmost.note("org.example.other")
        home.record(appManagement: .missing)
        frontmost.note("com.apple.systempreferences")
        frontmost.note("com.tuguidragos.Peel")
        home.followSystemSettings()
        #expect(home.status(of: .appManagement) == "Known again once Peel moves another developer’s app")
    }

    @Test func neverHavingAskedIsNotWaiting() throws {
        let madeUp = try MadeUpDefaults()
        defer { madeUp.forget() }
        let frontmost = FrontmostApp(observing: false)
        let home = HomeModel(helper: HelperModel(), defaults: madeUp.defaults, frontmost: frontmost)

        #expect(!home.appManagementAwaitsARemoval)
        #expect(!home.waitingRequired.contains(.appManagement))
    }

    @Test func theRowsDontWaitForTheQuestionAboutAnotherCopy() async throws {
        let madeUp = try MadeUpDefaults()
        defer { madeUp.forget() }
        let (gate, opens) = AsyncStream.makeStream(of: Void.self)
        let home = HomeModel(
            helper: HelperModel(), defaults: madeUp.defaults, readsFinderExtension: (
                isEnabled: { false },
                runsFromAnotherCopy: {
                    for await _ in gate {}
                    return true
                }
            ), readsModelName: { nil }
        )

        let refresh = Task { await home.refresh() }
        while !home.hasChecked { await Task.yield() }
        #expect(!home.isFinderExtensionFromAnotherCopy)
        opens.finish()
        await refresh.value

        #expect(home.isFinderExtensionFromAnotherCopy)
    }

    @Test func asksForTheMacsNameOnceALaunchWhenNothingAnswers() async throws {
        let madeUp = try MadeUpDefaults()
        defer { madeUp.forget() }
        let asked = Mutex(0)
        let home = HomeModel(helper: HelperModel(), defaults: madeUp.defaults, readsModelName: {
            asked.withLock { $0 += 1 }
            return nil
        })

        await home.refresh()
        await home.refresh()

        #expect(asked.withLock { $0 } == 1)
    }
}
