import Foundation
@testable import Peel
import Sparkle
import Testing

struct PeelUpdaterTests {
    @Test func takesTheUpdatesItRemindsOfGentlyFromSparkle() {
        let updater = PeelUpdater()
        let takesThem = #selector(
            (any SPUStandardUserDriverDelegate).standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)
        )

        #expect(updater.supportsGentleScheduledUpdateReminders)
        #expect(updater.responds(to: takesThem))
    }

    /// Sparkle reads its settings from Peel's preferences before the Info.plist, and any program of the account can
    /// write those.
    @Test func handsSparkleItsOwnFeedAndNothingAboutThisMac() {
        let updater = PeelUpdater()
        let givesTheFeed = #selector((any SPUUpdaterDelegate).feedURLString(for:))
        let givesTheProfile = #selector((any SPUUpdaterDelegate).allowedSystemProfileKeys(for:))

        #expect(PeelUpdater.feed == "https://github.com/TuguiDragos/Peel/releases/latest/download/appcast.xml")
        #expect(updater.responds(to: givesTheFeed))
        #expect(updater.responds(to: givesTheProfile))
    }

    @Test func tellsAServerOnlyThatPeelAsksAndKeepsNoCookie() {
        let updater = PeelUpdater()
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: updater, userDriverDelegate: updater
        )
        let policy = HTTPCookieStorage.shared.cookieAcceptPolicy
        defer { HTTPCookieStorage.shared.cookieAcceptPolicy = policy }
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always

        PeelUpdater.configure(controller.updater)

        #expect(controller.updater.userAgentString == "Peel")
        #expect(controller.updater.httpHeaders == ["Accept-Language": "*"])
        #expect(HTTPCookieStorage.shared.cookieAcceptPolicy == .never)
        #expect(HTTPCookieStorage.shared.cookies?.isEmpty != false)
    }

    @Test func asksOnItsOwnOnlyWhileUpdateChecksAreOn() throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let updater = PeelUpdater(defaults: made.defaults)
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: updater, userDriverDelegate: updater
        )

        made.defaults.set(false, forKey: SettingsKey.checksForAppUpdates)
        #expect(throws: (any Error).self) { try updater.updater(controller.updater, mayPerform: .updatesInBackground) }
        #expect(throws: (any Error).self) { try updater.updater(controller.updater, mayPerform: .updateInformation) }
        #expect(throws: Never.self) { try updater.updater(controller.updater, mayPerform: .updates) }
        made.defaults.set(true, forKey: SettingsKey.checksForAppUpdates)
        #expect(throws: Never.self) { try updater.updater(controller.updater, mayPerform: .updatesInBackground) }
    }

    @Test func forgetsTheSettingsItNeverWritesAndNoOther() throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        made.defaults.set(false, forKey: "SUEnableAutomaticChecks")
        made.defaults.set(31_536_000, forKey: "SUScheduledCheckInterval")
        made.defaults.set("2.0", forKey: "SUSkippedVersion")

        PeelUpdater.forgetSettingsLeftToTheInfoPlist(in: made.defaults)

        #expect(made.defaults.object(forKey: "SUEnableAutomaticChecks") == nil)
        #expect(made.defaults.object(forKey: "SUScheduledCheckInterval") == nil)
        #expect(made.defaults.string(forKey: "SUSkippedVersion") == "2.0")
    }
}
