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
        let earlier = IconCache.icon(for: app)
        #expect(IconCache.icon(for: app) === earlier)

        made.defaults.set("ClearLight", forKey: "AppleIconAppearanceTheme")
        for _ in 0..<10_000 where style.revision == 0 { await Task.yield() }

        #expect(style.revision > 0)
        #expect(IconCache.icon(for: app) !== earlier)
    }
}
