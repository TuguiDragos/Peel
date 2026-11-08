import Foundation
@testable import Peel
import PeelCore
import Synchronization
import Testing

@MainActor
struct BulkRemovalPlanTests {
    @Test func followsASystemExtensionTurnedOffWhilePeelWasAway() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "BulkRemovalPlanTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "Example.app", directoryHint: .isDirectory)
        let helper = url.appending(path: "Contents/MacOS/Helper.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        let app = InstalledApp(url: url, bundleIdentifier: "org.example.app", name: "Example", teamIdentifier: "ABCDE12345")
        let election = Mutex(AppExtension.Election.on)
        let plan = BulkRemovalPlan(apps: [app]) {
            [AppExtension(
                identifier: "org.example.guard", name: "Example Guard", kind: .systemExtension, point: nil, owner: nil,
                url: nil, election: election.withLock { $0 }, teamIdentifier: "ABCDE12345", reportedState: nil,
                installedFor: helper.path(percentEncoded: false)
            )]
        }
        await plan.refresh(installedApps: [app], canUseHelper: false)
        #expect(plan.items.first { $0.url == url }?.removedElsewhere != nil)
        #expect(!plan.selectedURLs.contains(url))

        election.withLock { $0 = .off }
        await plan.followSystemExtensions()

        #expect(plan.items.first { $0.url == url }?.removedElsewhere == nil)
        #expect(plan.selectedURLs.contains(url))
    }
}
