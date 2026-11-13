import Foundation
@testable import Peel
import PeelCore
import Testing

struct PackageQuitTitleTests {
    @Test func asksOnlyWhatAnUninstallAsksToQuit() async {
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.app", name: "Example"
        )
        let running = [
            RunningCopies.Process(identifier: 1, bundleIdentifier: "org.example.app", bundleURL: app.url),
            RunningCopies.Process(
                identifier: 2, bundleIdentifier: "org.example.app.finder",
                bundleURL: app.url.appending(path: "Contents/PlugIns/Finder.appex", directoryHint: .isDirectory)
            ),
        ]

        let asked = await PackageDetailView.toQuit([app, app], among: running, installedApps: [app])

        #expect(asked.map(\.identifier) == [1])
    }

    /// The button already says Quit Apps for several, and "it" is wrong for them in every language.
    @Test func severalAppsAreAskedInThePlural() {
        #expect(PackageDetailView.quitTitle(names: "Alpha and Beta", several: true).key == "Quit these apps before removing them.")
        #expect(PackageDetailView.quitTitle(names: "Alpha", several: false).key == "Quit %@ before removing it.")
    }
}
