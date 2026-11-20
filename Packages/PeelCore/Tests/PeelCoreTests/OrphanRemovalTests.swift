import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct OrphanRemovalTests {
    /// The list was made before the app was installed again, so part of it belongs to an installed app and stays.
    @Test func leavesWhatAnAppInstalledSinceTheScanClaims() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Preferences/com.back.again.plist")
        try directory.file("home/Library/Caches/com.gone.app/cache.db")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let scanner = OrphanScanner(environment: environment) { _ in false }
        let listed = await scanner.scan(installedApps: []).groups.flatMap(\.items)
        let moved = Mutex<[String]>([])
        let trash = TrashService(environment: environment) { url in
            moved.withLock { $0.append(url.lastPathComponent) }
            return url
        }

        let back = InstalledApp(url: URL(filePath: "/Applications/Back.app"), bundleIdentifier: "com.back.again", name: "Back")
        let result = await OrphanRemoval.trash(
            listed,
            installedApps: [back],
            remembered: [],
            scanner: scanner,
            using: trash,
            mayUseHelper: true
        )

        #expect(moved.withLock { $0 } == ["com.gone.app"])
        #expect(result.trashed.map(\.originalURL.lastPathComponent) == ["com.gone.app"])
        #expect(result.failures.map(\.url.lastPathComponent) == ["com.back.again.plist"])
        #expect(result.failures.first?.reason == .claimedSinceScan)
    }

    /// The scan reached it through real folders alone, so a link on its way now became one since the scan.
    @Test func leavesWhatAFolderOnItsWayNowLeadsElsewhereFor() async throws {
        let directory = try TemporaryDirectory()
        let support = try directory.directory("home/Library/Application Support")
        try directory.file("home/Library/Application Support/Example Software/org.example.mixer/settings.json")
        let elsewhere = try directory.file("elsewhere/Example Software/org.example.mixer/settings.json")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let scanner = OrphanScanner(environment: environment) { _ in false }
        let gone = RememberedApp(
            bundleIdentifier: "org.example.mixer", name: "Mixer", teamIdentifier: nil, lastSeen: .now,
            lastPath: "/Applications/Mixer.app"
        )
        let listed = await scanner.scan(installedApps: [], remembered: [gone]).groups.flatMap(\.items)
        let item = try #require(listed.first { $0.url.lastPathComponent == "org.example.mixer" })
        #expect(item.foundBelow.map(PathPattern.comparablePath(of:)) == PathPattern.comparablePath(of: support))
        let folder = support.appending(path: "Example Software")
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(
            at: folder, withDestinationURL: elsewhere.deletingLastPathComponent().deletingLastPathComponent()
        )
        let trash = TrashService(environment: environment) { url in url }

        let result = await OrphanRemoval.trash(
            [item], installedApps: [], remembered: [gone], scanner: scanner, using: trash, mayUseHelper: true
        )

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.linkOnTheWay])
        #expect(!elsewhere.isMissing)
    }

    @Test func leavesAFolderThatBecameALinkSinceTheScan() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("home/Library/Caches/org.example.mixer")
        try directory.file("home/Library/Caches/org.example.mixer/cache.db")
        let real = try directory.directory("elsewhere").appending(path: "real")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let scanner = OrphanScanner(environment: environment) { _ in false }
        let gone = RememberedApp(
            bundleIdentifier: "org.example.mixer", name: "Mixer", teamIdentifier: nil, lastSeen: .now,
            lastPath: "/Applications/Mixer.app"
        )
        let listed = await scanner.scan(installedApps: [], remembered: [gone]).groups.flatMap(\.items)
        let item = try #require(listed.first { $0.url.lastPathComponent == "org.example.mixer" })
        try FileManager.default.moveItem(at: folder, to: real)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: real)
        let trash = TrashService(environment: environment) { url in url }

        let result = await OrphanRemoval.trash(
            [item], installedApps: [], remembered: [gone], scanner: scanner, using: trash, mayUseHelper: true
        )

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.changedSinceScan])
        #expect(folder.isSymbolicLink && !real.appending(path: "cache.db").isMissing)
    }

    @Test(.permissionsHold) func whatNeedsAnAdministratorStaysWhenTheHelperMayNotBeUsed() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.gone.app/cache.db")
        let served = try directory.directory("root/Library/Application Support/com.gone.app")
        try directory.setPermissions(0o555, of: served)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: served.path(percentEncoded: false)
            )
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let scanner = OrphanScanner(environment: environment) { _ in false }
        let listed = await scanner.scan(installedApps: []).groups.flatMap(\.items)
        let helperWasAsked = Mutex<[URL]>([])
        let trash = TrashService(environment: environment, moveThroughHelper: { urls in
            helperWasAsked.withLock { $0 += urls }
            return TrashResult()
        }) { url in url }
        let privileged = listed.filter(\.requiresPrivileges).map(\.url)
        #expect(!privileged.isEmpty, "the fixture needs an item only an administrator can move")

        let result = await OrphanRemoval.trash(
            listed,
            installedApps: [],
            remembered: [],
            scanner: scanner,
            using: trash,
            mayUseHelper: false
        )

        #expect(helperWasAsked.withLock { $0 }.isEmpty)
        #expect(result.failures.map(\.url) == privileged)
        #expect(result.failures.allSatisfy { $0.reason == .needsHelper })

        _ = await OrphanRemoval.trash(
            listed, installedApps: [], remembered: [], scanner: scanner, using: trash, mayUseHelper: true
        )
        #expect(helperWasAsked.withLock { $0 } == privileged)
    }
}
