import Foundation
@testable import Peel
import Testing

@MainActor
struct FoundLastTimeStoreTests {
    @Test func aLookThatFindsTheSameWritesNothing() throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let store = FoundLastTimeStore(defaults: made.defaults)

        store.record(Looked(count: 3, size: nil), for: .orphans)
        let written = try #require(made.defaults.data(forKey: "home.foundLastTime"))
        store.record(Looked(count: 3, size: nil), for: .orphans)
        #expect(made.defaults.data(forKey: "home.foundLastTime") == written)

        store.record(Looked(count: 4, size: nil), for: .orphans)
        #expect(made.defaults.data(forKey: "home.foundLastTime") != written)
    }
}
