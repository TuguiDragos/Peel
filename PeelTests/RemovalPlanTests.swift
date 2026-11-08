import AppKit
@testable import Peel
import PeelCore
import Synchronization
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

    @Test func followsASystemExtensionTurnedOffWhilePeelWasAway() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "RemovalPlanTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "Example.app", directoryHint: .isDirectory)
        let helper = url.appending(path: "Contents/MacOS/Helper.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        let app = InstalledApp(url: url, bundleIdentifier: "org.example.app", name: "Example", teamIdentifier: "ABCDE12345")
        let election = Mutex(AppExtension.Election.on)
        let plan = RemovalPlan(app: app, jobsKeptRunning: { _ in [] }) {
            [AppExtension(
                identifier: "org.example.guard", name: "Example Guard", kind: .systemExtension, point: nil, owner: nil,
                url: nil, election: election.withLock { $0 }, teamIdentifier: "ABCDE12345", reportedState: nil,
                installedFor: helper.path(percentEncoded: false)
            )]
        }
        await plan.refresh(installedApps: [app], canUseHelper: false)
        #expect(plan.removedElsewhere != nil)
        #expect(!plan.selectedURLs.contains(url))

        election.withLock { $0 = .off }
        await plan.followSystemExtensions()

        #expect(plan.removedElsewhere == nil)
        #expect(plan.selectedURLs.contains(url))
    }
}
