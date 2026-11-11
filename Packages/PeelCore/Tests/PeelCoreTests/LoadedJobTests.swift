import Foundation
@testable import PeelCore
import Testing

struct LoadedJobTests {
    private func job(_ label: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["Label": label, "Program": "/Library/Application Support/Tide/tided"],
            format: .xml, options: 0
        )
    }

    @Test func aRowWhoseJobLaunchdHasLoadedSaysSo() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: try directory.directory("root/Applications/Tide.app"), bundleIdentifier: "org.example.tide",
            name: "Tide"
        )
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        try directory.file("home/Library/LaunchAgents/org.example.tide.agent.plist", contents: job("org.example.tide.agent"))
        try directory.file("home/Library/LaunchAgents/org.example.tide.idle.plist", contents: job("org.example.tide.idle"))
        try directory.file("root/Library/LaunchDaemons/org.example.tide.daemon.plist", contents: job("org.example.tide.daemon"))

        let plan = await LaunchdCleanup.$loadedStandIn.withValue({ $0.label != "org.example.tide.idle" }) {
            await Uninstallation.prepare(app, installedApps: [app], environment: environment)
        }
        let loaded = Dictionary(
            uniqueKeysWithValues: plan.scan.leftovers.map { ($0.url.lastPathComponent, $0.isALoadedJob) }
        )

        #expect(loaded["org.example.tide.agent.plist"] == true)
        #expect(loaded["org.example.tide.daemon.plist"] == true)
        #expect(loaded["org.example.tide.idle.plist"] == false)
    }
}
