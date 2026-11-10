import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct AppCatalogTests {
    @MainActor @Test func anAppShownFromElsewhereIsLookedForOffTheMainThread() async throws {
        let directory = try TemporaryDirectory()
        let there = try directory.directory("Elsewhere/There.app")
        let gone = directory.url.appending(path: "Elsewhere/Gone.app")
        let lookedOnMain = Mutex<Bool?>(nil)

        let found = await AppCatalog.gone([there, gone]) { url in
            lookedOnMain.withLock { $0 = Thread.isMainThread }
            return url.isMissing
        }

        #expect(found == [gone])
        #expect(lookedOnMain.withLock { $0 } == false, "the window waits for a disk that may not answer")
    }

    @Test func readsAFolderGivenAsALink() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("elsewhere/Example.app")
        try directory.directory("elsewhere/Tools/Other.app")
        let target = directory.url.appending(path: "elsewhere", directoryHint: .isDirectory)
        let link = directory.url.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "Applications").path(percentEncoded: false),
            withDestinationPath: "elsewhere"
        )

        let found = AppCatalog.appBundles(in: link)

        #expect(found.unreadable.isEmpty)
        #expect(Set(found.bundles.map(\.lastPathComponent)) == ["Example.app", "Other.app"])
        let place = PathPattern.comparablePath(of: target)
        #expect(found.bundles.allSatisfy { $0.path(percentEncoded: false).hasPrefix(place) })
    }

    @Test func aLinkThatLeadsNowhereHoldsNoApp() throws {
        let directory = try TemporaryDirectory()
        let link = directory.url.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "Applications").path(percentEncoded: false),
            withDestinationPath: "/Volumes/org-example-not-connected/Applications"
        )

        let found = AppCatalog.appBundles(in: link)

        #expect(found.unreadable.isEmpty)
        #expect(found.bundles.isEmpty)
    }

    @Test func findsTheAppsOfAFolderThrownAwayButNoneThroughALinkAPackageOrAHiddenFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Trash/Suite/Suite.app/Contents")
        try directory.directory("Trash/Suite/Tools/Helper.app/Contents")
        try directory.directory("Trash/Suite.bundle/Inside.app/Contents")
        try directory.directory("Trash/.Hidden/Inside.app/Contents")
        try directory.directory("Installed/Kept/Kept.app/Contents")
        let link = directory.url.appending(path: "Trash/Kept", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: directory.url.appending(path: "Installed/Kept")
        )
        let trash = directory.url.appending(path: "Trash", directoryHint: .isDirectory)

        let suite = await AppCatalog.apps(
            inAFolderThrownAway: trash.appending(path: "Suite", directoryHint: .isDirectory)
        )
        let others = await [
            AppCatalog.apps(inAFolderThrownAway: link),
            AppCatalog.apps(inAFolderThrownAway: trash.appending(path: "Suite.bundle", directoryHint: .isDirectory)),
            AppCatalog.apps(inAFolderThrownAway: trash.appending(path: ".Hidden", directoryHint: .isDirectory)),
        ]

        #expect(suite.map(\.lastPathComponent).sorted() == ["Helper.app", "Suite.app"])
        #expect(others == [[], [], []])
    }

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

        // Tunewell is read for real, so it gets Peel's own budget: on a busy runner a reading takes more than 0.2 s.
        let scan = await AppCatalog.scan(in: [answering, sleeping], within: FileSize.budget) { folder, isGivenUp in
            guard folder == sleeping else { return AppCatalog.appBundles(in: folder, unless: isGivenUp) }
            _ = released.wait(timeout: .now() + 30)
            return ([], [])
        }

        #expect(scan.apps.map(\.name) == ["Tunewell"])
        #expect(scan.unreadable == [sleeping])
        #expect(!scan.needsFullDiskAccess)
    }

    @Test func aChosenFolderWhoseAppsDoNotAnswerCostsOneWaitAndIsSaid() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Tools")
        let bundles = (0..<40).map { folder.appending(path: "App \($0).app", directoryHint: .isDirectory) }
        let asked = Mutex(0)
        let released = DispatchSemaphore(value: 0)
        defer { for _ in 0..<40 { released.signal() } }

        let scan = await AppCatalog.scan(
            in: [folder], within: 0.2, walking: { _, _ in (bundles, []) },
            reading: { _ in
                asked.withLock { $0 += 1 }
                _ = released.wait(timeout: .now() + 30)
                return nil
            }
        )

        #expect(scan.apps.isEmpty)
        #expect(Set(scan.unreadable) == Set(bundles))
        #expect(asked.withLock { $0 } <= max(ProcessInfo.processInfo.activeProcessorCount, 2))
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
