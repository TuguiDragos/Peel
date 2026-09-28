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
        let result = await OrphanRemoval.trash(listed, installedApps: [back], scanner: scanner, using: trash, mayUseHelper: true)

        #expect(moved.withLock { $0 } == ["com.gone.app"])
        #expect(result.trashed.map(\.originalURL.lastPathComponent) == ["com.gone.app"])
        #expect(result.failures.map(\.url.lastPathComponent) == ["com.back.again.plist"])
        #expect(result.failures.first?.reason == .claimedSinceScan)
    }

    @Test(.permissionsHold) func whatNeedsAnAdministratorStaysWhenTheHelperMayNotBeUsed() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.gone.app/cache.db")
        let served = try directory.directory("root/Library/Application Support/com.gone.app")
        try directory.setPermissions(0o555, of: served)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: served.path(percentEncoded: false)) }
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

        let result = await OrphanRemoval.trash(listed, installedApps: [], scanner: scanner, using: trash, mayUseHelper: false)

        #expect(helperWasAsked.withLock { $0 }.isEmpty)
        #expect(result.failures.map(\.url) == privileged)
        #expect(result.failures.allSatisfy { $0.reason == .needsHelper })

        _ = await OrphanRemoval.trash(listed, installedApps: [], scanner: scanner, using: trash, mayUseHelper: true)
        #expect(helperWasAsked.withLock { $0 } == privileged)
    }
}
