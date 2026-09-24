import Foundation
@testable import PeelCore
import Testing

struct AppOrderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func app(_ name: String, lastUsed: Date? = nil, added: Date? = nil) -> InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/\(name).app"), bundleIdentifier: "com.example.\(name)", name: name, lastUsedDate: lastUsed, dateAdded: added)
    }

    @Test func breaksATieTheWayTheListByNameReads() {
        let apps = [app("Zed"), app("arc"), app("Bear"), app("Big")]
        let sizes = ["Big": 10]

        #expect(AppOrder.sorted(apps) { sizes[$0.name] ?? 0 }.map(\.name) == ["Big", "arc", "Bear", "Zed"])
    }

    @Test func countsAnAppNobodyEverOpenedFromTheDayItWasAdded() {
        let longAgo = now.addingTimeInterval(-400 * 86_400)
        let lastWeek = now.addingTimeInterval(-7 * 86_400)

        #expect(AppOrder.isUnused(app("Old", lastUsed: longAgo), forMonths: 6, now: now))
        #expect(!AppOrder.isUnused(app("Used", lastUsed: lastWeek, added: longAgo), forMonths: 6, now: now))
        #expect(AppOrder.isUnused(app("Never", added: longAgo), forMonths: 6, now: now), "never opened, and left out of the filter meant to find it")
        #expect(!AppOrder.isUnused(app("New", added: lastWeek), forMonths: 6, now: now))
        #expect(!AppOrder.isUnused(app("Unknown"), forMonths: 6, now: now))
    }
}
