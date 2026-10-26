import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct AppCatalogTests {
    private let yesterday = Date(timeIntervalSince1970: 1_800_000_000)
    private let today = Date(timeIntervalSince1970: 1_800_086_400)

    private func app(
        _ name: String,
        version: String = "1.0",
        lastUsed: Date? = nil,
        isRecorded: Bool = true
    ) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.\(name)", name: name, version: version, lastUsedDate: lastUsed,
            isUseRecorded: isRecorded
        )
    }

    @Test func aFolderThatDoesNotAnswerIsNamedAndTheOthersAreListed() async throws {
        let directory = try TemporaryDirectory()
        let answering = try directory.directory("Apps")
        try directory.file(
            "Apps/Tunewell.app/Contents/Info.plist",
            contents: PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "org.example.tunewell", "CFBundleName": "Tunewell"],
                format: .xml, options: 0
            )
        )
        let sleeping = directory.url.appending(path: "Sleeping", directoryHint: .isDirectory)
        let released = DispatchSemaphore(value: 0)
        defer { released.signal() }

        let scan = await AppCatalog.scan(in: [answering, sleeping], within: 0.2) { folder, isGivenUp in
            guard folder == sleeping else { return AppCatalog.appBundles(in: folder, unless: isGivenUp) }
            _ = released.wait(timeout: .now() + 30)
            return ([], [])
        }

        #expect(scan.apps.map(\.name) == ["Tunewell"])
        #expect(scan.unreadable == [sleeping])
        #expect(!scan.needsFullDiskAccess)
    }

    @Test func aReadingStoppedWhileAFolderDoesNotAnswerReturnsAtOnce() async throws {
        let sleeping = URL(filePath: "/nowhere/Sleeping", directoryHint: .isDirectory)
        let asked = Mutex(false)
        let released = DispatchSemaphore(value: 0)
        defer { released.signal() }
        let clock = ContinuousClock()
        let reading = Task(priority: .userInitiated) {
            _ = await AppCatalog.scan(in: [sleeping], within: 3_600) { _, _ in
                asked.withLock { $0 = true }
                _ = released.wait(timeout: .now() + 30)
                return ([], [])
            }
            return clock.now
        }
        while !asked.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(2))
        }

        let stopped = clock.now
        reading.cancel()
        let returned = await reading.value

        #expect(returned - stopped < .seconds(1))
    }

    /// Opening an app changes when it was last opened and nothing about what is installed, so the pages that scan
    /// again whenever the apps change are not told they did.
    @Test func anAppOpenedAgainListsTheSameApps() {
        let listed = [app("Tunewell", lastUsed: yesterday), app("Zed")]
        let reading = [app("Tunewell", lastUsed: today), app("Zed", lastUsed: today)]

        #expect(AppCatalog.listsTheSameApps(reading, as: listed))
        #expect(AppCatalog.listsTheSameApps([app("Tunewell", isRecorded: false), app("Zed")], as: listed))
    }

    @Test func anotherBuildAnAppAddedOrAnAppGoneIsAnotherList() {
        let listed = [app("Tunewell"), app("Zed")]

        #expect(!AppCatalog.listsTheSameApps([app("Tunewell", version: "2.0"), app("Zed")], as: listed))
        #expect(!AppCatalog.listsTheSameApps([app("Arc"), app("Tunewell"), app("Zed")], as: listed))
        #expect(!AppCatalog.listsTheSameApps([app("Tunewell")], as: listed))
        #expect(AppCatalog.listsTheSameApps(listed, as: listed))
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
