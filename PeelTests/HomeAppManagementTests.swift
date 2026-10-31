import Foundation
@testable import Peel
import PeelCore
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

    @Test func neverHavingAskedIsNotWaiting() throws {
        let madeUp = try MadeUpDefaults()
        defer { madeUp.forget() }
        let frontmost = FrontmostApp(observing: false)
        let home = HomeModel(helper: HelperModel(), defaults: madeUp.defaults, frontmost: frontmost)

        #expect(!home.appManagementAwaitsARemoval)
        #expect(!home.waitingRequired.contains(.appManagement))
    }
}
