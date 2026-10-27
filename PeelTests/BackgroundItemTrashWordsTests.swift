import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct BackgroundItemTrashWordsTests {
    private func job(_ source: BackgroundItem.Source) -> BackgroundItem {
        BackgroundItem(
            label: "org.example.agent", kind: .agent, source: source, plistURL: URL(filePath: "/x/org.example.agent.plist"),
            program: "/usr/local/bin/agent", runsAtLoad: true, keepsAlive: false, ownerBundleIdentifier: nil,
            ownerName: nil, ownerURL: nil, isOrphan: false, state: .loaded, isDisabled: false
        )
    }

    @Test func saysWhatAMoveDoesForEveryAccountThatRunsTheAgent() {
        #expect(String(localized: job(.systemLibrary).whenTrashed) == String(localized: "Once the file is in the Trash, the item is stopped for you. Other accounts logged in now run it until they log out, and none starts it again."))
        #expect(String(localized: job(.userLibrary).whenTrashed) == String(localized: "Once the file is in the Trash, the item is stopped."))
    }

    @Test func promisesNoStopForARowNamedByItsFile() {
        var named = job(.userLibrary)
        named.state = .unknown
        named.isClosedToPeel = true
        named.isNamedByItsFile = true

        #expect(String(localized: named.whenTrashed) == String(localized: "macOS won’t start it again: it stops for good when the Mac restarts."))
    }
}
