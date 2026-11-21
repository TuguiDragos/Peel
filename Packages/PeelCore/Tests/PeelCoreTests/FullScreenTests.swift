import Foundation
import Testing

struct FullScreenTests {
    @Test func everyWindowOfPeelStaysOutOfFullScreen() throws {
        let app = try String(
            contentsOf: LineLengthTests.repository.appending(path: "Peel/PeelApp.swift"), encoding: .utf8
        )
        let body = try #require(app.range(of: "var body: some Scene {")).upperBound
        let scenes = try Regex(#"\n        (Window\(|WindowGroup|Settings \{|DocumentGroup|UtilityWindow)"#)
        let starts = app[body...].matches(of: scenes).map(\.range.lowerBound)

        #expect(starts.count == 3)
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : app.endIndex
            let scene = app[start..<end]
            #expect(scene.contains(".windowFullScreenBehavior(.disabled)"), "\(scene.prefix(60))")
        }
    }
}
