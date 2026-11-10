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
