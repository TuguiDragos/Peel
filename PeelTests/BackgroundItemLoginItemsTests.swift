import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct BackgroundItemLoginItemsTests {
    private func job(_ source: BackgroundItem.Source, at path: String) -> BackgroundItem {
        BackgroundItem(
            label: "org.example.agent", kind: .agent, source: source, plistURL: URL(filePath: path),
            program: "/usr/local/bin/agent", runsAtLoad: true, keepsAlive: false, ownerBundleIdentifier: nil,
            ownerName: nil, ownerURL: nil, isOrphan: false, state: .notLoaded, isDisabled: false
        )
    }

    @Test func asksSystemSettingsOnlyAboutAFileInTheFoldersItReads() async {
        let agents = URL.homeDirectory.appending(path: "Library/LaunchAgents/org.example.agent.plist")

        let elsewhere = await BackgroundItemDetailView.legacyStatus(of: job(.otherFile, at: "/Users/Shared/org.example.agent.plist"))
        let documented = await BackgroundItemDetailView.legacyStatus(of: job(.userLibrary, at: agents.path))

        #expect(elsewhere == nil)
        #expect(documented != nil)
    }
}
