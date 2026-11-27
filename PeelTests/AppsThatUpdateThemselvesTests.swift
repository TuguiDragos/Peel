import Foundation
@testable import Peel
@testable import PeelCore
import Testing

/// An app that updates itself outside its bundle, as Obsidian does, changes nothing in the folders of apps.
@Suite(.serialized) struct AppsThatUpdateThemselvesTests {
    /// A library over a made-up home and a chosen folder that holds one app with Obsidian's loader, at 1.15.0.
    private struct MadeUp {
        let folder: URL
        let home: URL
        let chosen: URL
        let defaults: MadeUpDefaults
        let library: AppLibrary

        init() throws {
            folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
            home = folder.appending(path: "home", directoryHint: .isDirectory)
            chosen = folder.appending(path: "Chosen", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try Self.install("Jotter", identifier: "org.example.jotter", loaderVersion: "1.15.0", in: chosen)
            defaults = try MadeUpDefaults()
            defaults.defaults.set(false, forKey: SettingsKey.checksForAppUpdates)
            library = AppLibrary(
                defaults: defaults.defaults,
                releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "release-notes.json")),
                appFolders: AppFolders(url: folder.appending(path: "app-folders.json")),
                appMemory: AppMemory(url: folder.appending(path: "apps.json")),
                home: home
            )
            library.addFolders([chosen])
        }

        func forget() {
            defaults.forget()
            try? FileManager.default.removeItem(at: folder)
        }

        var jotter: InstalledApp? {
            library.apps.first { $0.bundleIdentifier == "org.example.jotter" }
        }

        /// What the loader finds once the app has downloaded `version` for itself.
        func download(_ version: String) throws {
            let data = home.appending(path: "Library/Application Support/obsidian", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            try Data().write(to: data.appending(path: "obsidian-\(version).asar"))
        }

        static func install(_ name: String, identifier: String, loaderVersion: String?, in folder: URL) throws {
            let contents = folder.appending(path: "\(name).app/Contents", directoryHint: .isDirectory)
            let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let info: [String: Any] = [
                "CFBundleIdentifier": identifier, "CFBundleName": name, "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": loaderVersion ?? "1.0", "CFBundleVersion": "100",
            ]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
            guard let loaderVersion else { return }
            let package = try JSONSerialization.data(withJSONObject: ["name": "obsidian", "version": loaderVersion])
            try archive(holding: package, named: "package.json").write(to: resources.appending(path: "app.asar"))
            try Data().write(to: resources.appending(path: "obsidian.asar"))
        }

        /// An archive laid out as `asar` writes one: the index's size, the index as JSON, then the file.
        private static func archive(holding file: Data, named name: String) throws -> Data {
            let index = try JSONSerialization.data(
                withJSONObject: ["files": [name: ["size": file.count, "offset": "0"]]]
            )
            let padding = (4 - index.count % 4) % 4
            func number(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
            let header = number(4 + index.count + padding) + number(index.count) + index + Data(count: padding)
            return number(4) + number(header.count) + header + file
        }
    }

    @Test func aPageIsMadeAnewForAnotherBuildAndForNothingElse() {
        func app(
            version: String = "1.15.0", running: String? = nil, build: String = "100", team: String? = "ABCDE12345",
            architectures: Set<Architecture> = [.arm64], opened: Date? = nil
        ) -> InstalledApp {
            InstalledApp(
                url: URL(filePath: "/Applications/Jotter.app"), bundleIdentifier: "org.example.jotter", name: "Jotter",
                version: version, runningVersion: running, buildVersion: build, teamIdentifier: team,
                architectures: architectures, lastUsedDate: opened
            )
        }
        let page = ContentView.page(of: app())

        #expect(ContentView.page(of: app(running: "1.15.1")) != page)
        #expect(ContentView.page(of: app(version: "1.16.0")) != page)
        #expect(ContentView.page(of: app(build: "101")) != page)
        #expect(ContentView.page(of: app(team: "ZYXWV98765")) != page)
        #expect(ContentView.page(of: app(architectures: [.arm64, .x86_64])) != page)
        #expect(ContentView.page(of: app(opened: .now)) == page)
    }

    @Test(.timeLimit(.minutes(1))) func anAppThatUpdatedItselfIsSeenWhenPeelComesForward() async throws {
        let madeUp = try MadeUp()
        defer { madeUp.forget() }
        await madeUp.library.load()
        let listed = try #require(madeUp.jotter)
        #expect(listed.version == "1.15.0" && listed.runningVersion == nil)

        try madeUp.download("1.15.1")
        await madeUp.library.refreshUnlessRecent()

        #expect(madeUp.jotter?.runningVersion == "1.15.1")
    }

    @Test(.timeLimit(.minutes(1))) func aRecentReadingIsEnoughWhileNoAppUpdatedItself() async throws {
        let madeUp = try MadeUp()
        defer { madeUp.forget() }
        await madeUp.library.load()
        try #require(madeUp.jotter != nil)

        try MadeUp.install("Later", identifier: "org.example.later", loaderVersion: nil, in: madeUp.chosen)
        await madeUp.library.refreshUnlessRecent()

        #expect(!madeUp.library.apps.contains { $0.bundleIdentifier == "org.example.later" })
    }

    @Test(.timeLimit(.minutes(1))) func theRoundOfTheHourLearnsFirstOfAnAppThatUpdatedItself() async throws {
        let madeUp = try MadeUp()
        defer { madeUp.forget() }
        let (heard, tell) = AsyncStream.makeStream(of: [String].self)
        let following = Task { await madeUp.library.followChanges { tell.yield($0.map(\.name)) } }
        defer { following.cancel() }
        var next = heard.makeAsyncIterator()
        await madeUp.library.load()

        await madeUp.library.readAgainIfAnAppUpdatedItself()
        #expect(madeUp.jotter?.runningVersion == nil)

        try madeUp.download("1.15.1")
        await madeUp.library.readAgainIfAnAppUpdatedItself()

        try #require(madeUp.jotter?.runningVersion == "1.15.1")
        #expect(await next.next()?.contains("Jotter") == true, "what was learned of the old version is asked again")
    }
}
