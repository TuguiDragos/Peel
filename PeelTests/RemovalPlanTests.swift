import AppKit
@testable import Peel
import PeelCore
import Testing

@MainActor
struct RemovalPlanTests {
    private let thisApp = InstalledApp(
        url: Bundle.main.bundleURL, bundleIdentifier: Bundle.main.bundleIdentifier, name: "Peel"
    )

    @Test func asksAnAppToQuitUnlessLaunchdKeepsItRunning() async {
        let open = RemovalPlan(app: thisApp) { _ in [] }
        let kept = RemovalPlan(app: thisApp) { _ in [getpid()] }

        #expect(await open.processesToQuit().contains(.current))
        #expect(await !kept.processesToQuit().contains(.current))
    }
}
