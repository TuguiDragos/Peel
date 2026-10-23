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
}
