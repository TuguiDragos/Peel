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
        let result = await OrphanRemoval.trash(listed, installedApps: [back], scanner: scanner, using: trash)

        #expect(moved.withLock { $0 } == ["com.gone.app"])
        #expect(result.trashed.map(\.originalURL.lastPathComponent) == ["com.gone.app"])
        #expect(result.failures.map(\.url.lastPathComponent) == ["com.back.again.plist"])
        #expect(result.failures.first?.reason == .claimedSinceScan)
    }
}
