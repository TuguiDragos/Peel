import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct BackgroundItemLibraryTests {
    @Test func anEnabledJobThatLeftTheListSaysWhenItComesBack() {
        let job = BackgroundItem(
            label: "org.example.agent", kind: .agent, source: .app, plistURL: nil, program: nil, runsAtLoad: nil,
            keepsAlive: nil, ownerBundleIdentifier: "org.example.app", ownerName: "App",
            ownerURL: URL(filePath: "/Applications/App.app", directoryHint: .isDirectory), isOrphan: false,
            state: .notLoaded, isDisabled: true
        )

        let left = BackgroundItemLibrary.alertAfterEnabling(job, listed: [])
        guard case .enabledUntilLoaded(let label, let kind)? = left else {
            Issue.record("no alert for a job that left the list")
            return
        }
        #expect(label == "org.example.agent" && kind == .agent)
        #expect(BackgroundItemLibrary.alertAfterEnabling(job, listed: [job]) == nil)
    }
}
