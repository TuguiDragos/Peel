import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct BackgroundItemLibraryTests {
    private let job = BackgroundItem(
        label: "org.example.agent", kind: .agent, source: .app, plistURL: nil, program: nil, runsAtLoad: nil,
        keepsAlive: nil, ownerBundleIdentifier: "org.example.app", ownerName: "App",
        ownerURL: URL(filePath: "/Applications/App.app", directoryHint: .isDirectory), isOrphan: false,
        state: .notLoaded, isDisabled: true
    )

    private final class Reads {
        var count = 0
        var library: BackgroundItemLibrary?
        var wereShownAsAScan: [Bool] = []
    }

    @Test func readsTheListAgainWithoutShowingAScan() async {
        let reads = Reads()
        let job = job
        let library = BackgroundItemLibrary { _, _ in
            reads.count += 1
            reads.wereShownAsAScan.append(reads.library?.isScanning == true)
            return BackgroundItems.Scan(items: reads.count > 1 ? [job] : [])
        }
        reads.library = library

        await library.readAgain(installedApps: [])
        #expect(reads.count == 0, "nothing is read again before the list was read once")

        await library.refresh(installedApps: [])
        let scans = library.scans
        await library.readAgain(installedApps: [])

        #expect(library.items?.map(\.label) == [job.label])
        #expect(library.scans == scans + 1, "the item's page asks macOS again")
        #expect(reads.wereShownAsAScan == [true, false], "a read again is announced to nobody")
    }

    @Test func anEnabledJobThatLeftTheListSaysWhenItComesBack() {
        let left = BackgroundItemLibrary.alertAfterEnabling(job, listed: [])
        guard case .enabledUntilLoaded(let label, let kind)? = left else {
            Issue.record("no alert for a job that left the list")
            return
        }
        #expect(label == "org.example.agent" && kind == .agent)
        #expect(BackgroundItemLibrary.alertAfterEnabling(job, listed: [job]) == nil)
    }
}
