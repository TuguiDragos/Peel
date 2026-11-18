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

    @Test func aJobWhoseAppLeftGivesTheMakersStepForWhatIsLeft() throws {
        let box = URL(filePath: "/Applications/Box.app", directoryHint: .isDirectory)
        var leftover = job(of: box, identifier: "com.box.desktop")
        leftover.appThatLeft = RememberedApp(
            bundleIdentifier: "com.box.desktop", name: "Box", teamIdentifier: "M683GB7CPW", lastSeen: .now,
            lastPath: "/Applications/Box.app"
        )
        leftover.makersUninstallerForWhatIsLeft = leftover.appThatLeft
            .flatMap { MakersUninstaller.ofWhatIsLeft(by: $0) }

        let found = try #require(BackgroundItemDetailView.makersUninstaller(of: leftover, among: []))

        #expect(found.name == "Box")
        #expect(found.isForWhatIsLeft)
        #expect(found.uninstaller.step == .fromTheMakersPage)
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
        #expect(found?.name == "Kaspersky")
        #expect(found?.uninstaller.maker == "Kaspersky")
        let backup = job(of: other.url, identifier: "org.example.backup")
        #expect(BackgroundItemDetailView.makersUninstaller(of: backup, among: apps) == nil)
        #expect(BackgroundItemDetailView.makersWarning(app: "Kaspersky").contains("Kaspersky"))
    }
}
