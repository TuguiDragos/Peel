import Foundation
@testable import PeelCore
import Testing

struct AppCatalogTests {
    private func app(_ name: String) -> InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory), bundleIdentifier: "org.example.\(name)", name: name)
    }

    /// A folder's URL ends in a slash, as the catalog reads it, and a plug-in inside the app still belongs to it.
    @Test func findsTheAppABundleSitsInside() {
        let apps = [app("Tunewell"), app("Tunewell Extras")]
        let plugIn = URL(filePath: "/Applications/Tunewell.app/Contents/PlugIns/Bridge.bundle", directoryHint: .isDirectory)

        #expect(AppCatalog.app(holding: plugIn, among: apps)?.name == "Tunewell")
        #expect(AppCatalog.app(holding: apps[0].url, among: apps)?.name == "Tunewell")
        #expect(AppCatalog.app(holding: URL(filePath: "/Applications/Tunewell Extras.app/Contents/Info.plist"), among: apps)?.name == "Tunewell Extras")
        #expect(AppCatalog.app(holding: URL(filePath: "/Applications/Tunewell.application/x"), among: apps) == nil)
    }

    @Test func answersTheInnermostAppWhenAppsSitInsideEachOther() {
        let helper = InstalledApp(
            url: URL(filePath: "/Applications/Tunewell.app/Contents/Helpers/Agent.app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.Tunewell.Agent", name: "Agent"
        )
        let apps = [app("Tunewell"), helper]

        #expect(AppCatalog.app(holding: helper.url.appending(path: "Contents/MacOS/Agent"), among: apps)?.name == "Agent")
        #expect(AppCatalog.app(holding: URL(filePath: "/Applications/Tunewell.app/Contents/MacOS/Tunewell"), among: apps)?.name == "Tunewell")
    }
}
