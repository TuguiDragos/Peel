import Foundation
@testable import Peel
import PeelCore
import Testing

struct LifetimeStatsTests {
    @Test func eachFigureSaysThatItCountsWhatMoved() throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "LifetimeStatsTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let size = SizeTotal(known: 1_000, isComplete: true)

        try JSONEncoder().encode(RemovalTotals(bytes: size, items: 1, apps: 1, biggest: size))
            .write(to: folder.appending(path: "totals.json"))
        let stats = LifetimeStats(
            defaults: made.defaults, bundle: folder, history: folder.appending(path: "removals.json")
        )
        #expect(stats.appsLabel.key == "App moved")
        #expect(stats.itemsLabel.key == "Item moved")

        try JSONEncoder().encode(RemovalTotals(bytes: size, items: 9, apps: 2, biggest: size))
            .write(to: folder.appending(path: "totals.json"))
        stats.reload()
        #expect(stats.appsLabel.key == "Apps moved")
        #expect(stats.itemsLabel.key == "Items moved")
    }
}
