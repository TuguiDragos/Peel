import AppKit
import Foundation
@testable import Peel
import Testing

@Suite(.serialized) struct IconStyleTests {
    @Test func iconsAreMadeAgainWhenTheIconStyleChanges() async throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let style = IconStyle(defaults: made.defaults)
        let app = URL(filePath: "/System/Applications/Calculator.app", directoryHint: .isDirectory)
        let earlier = await built(app)
        #expect(IconCache.icon(for: app) === earlier)

        made.defaults.set("ClearLight", forKey: "AppleIconAppearanceTheme")
        for _ in 0..<10_000 where style.revision == 0 { await Task.yield() }

        #expect(style.revision > 0)
        #expect(await built(app) !== earlier)
    }

    @Test func anAppsOwnIconIsBuiltAwayFromTheMainThread() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let app = folder.appending(path: "Example.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(IconCache.icon(for: app) === IconCache.anyApp, "the row waited for the app's own icon")
        #expect(await built(app) !== IconCache.anyApp)
    }

    /// The icon `IconCache` gives `app` once one built away from the main thread has arrived.
    private func built(_ app: URL) async -> NSImage {
        let arrivals = IconArrivals.shared.count
        guard IconCache.icon(for: app) === IconCache.anyApp else { return IconCache.icon(for: app) }
        for await count in Observations({ IconArrivals.shared.count }) where count > arrivals {
            break
        }
        return IconCache.icon(for: app)
    }
}
