import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct BackgroundItemMakersTests {
    private func job(of owner: URL, identifier: String) -> BackgroundItem {
        BackgroundItem(
            label: "\(identifier).daemon", kind: .daemon, source: .systemLibrary, plistURL: nil,
            program: owner.appending(path: "Contents/MacOS/daemon").path(percentEncoded: false), runsAtLoad: true,
            keepsAlive: true, ownerBundleIdentifier: identifier, ownerName: nil, ownerURL: owner, isOrphan: false,
            state: .loaded, isDisabled: false
        )
    }

    @Test func aJobOfAnAppItsMakerRemovesSaysSo() {
        let agent = InstalledApp(
            url: URL(filePath: "/Applications/Kaspersky.app", directoryHint: .isDirectory),
            bundleIdentifier: "com.kaspersky.kav", name: "Kaspersky", teamIdentifier: "2Y8XE5CQ94", isSealIntact: true
        )
        let other = InstalledApp(
            url: URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.backup", name: "Example"
        )
        let apps = [agent, other]

        let kaspersky = job(of: agent.url, identifier: "com.kaspersky.kav")
        let found = BackgroundItemDetailView.makersUninstaller(of: kaspersky, among: apps)
        #expect(found?.app.name == "Kaspersky")
        #expect(found?.uninstaller.maker == "Kaspersky")
        let backup = job(of: other.url, identifier: "org.example.backup")
        #expect(BackgroundItemDetailView.makersUninstaller(of: backup, among: apps) == nil)
        #expect(BackgroundItemDetailView.makersWarning(app: "Kaspersky").contains("Kaspersky"))
    }
}
