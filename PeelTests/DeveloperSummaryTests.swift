import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct DeveloperSummaryTests {
    @Test func saysHowMuchOfWhatItFoundPeelRecommends() {
        let location = { (name: String, kind: DeveloperEnvironment.ContentKind, size: Int64) in
            DeveloperEnvironment.Location(
                url: URL(filePath: "/tmp/\(name)"), kind: kind, size: size, source: "https://example.com"
            )
        }
        let tool = { (locations: [DeveloperEnvironment.Location]) in
            DeveloperEnvironment(
                id: "org.example", name: "Example", systemImage: "hammer", appBundleIdentifiers: [], locations: locations
            )
        }
        let caches = tool([location("cache", .cache, 6_000_000_000)])
        let models = tool([location("model", .models, 89_000_000_000)])
        let words = { (environments: [DeveloperEnvironment]) in
            DeveloperLibrary.summary(of: environments).map { String($0.characters) }
        }

        let total = SizeTotal(known: 95_000_000_000, isComplete: true).text
        let recommended = SizeTotal(known: 6_000_000_000, isComplete: true).text
        #expect(words([caches, models]) == String(AttributedString(
            localized: "\(total) in ^[\(2) tool](inflect: true), \(recommended) of it recommended."
        ).characters))
        let alone = Tool.developer.summary(of: Looked(count: 1, size: caches.total)).map { String($0.characters) }
        #expect(words([caches]) == alone, "all of it recommended")
        let modelsTotal = SizeTotal(known: 89_000_000_000, isComplete: true).text
        #expect(words([models]) == String(AttributedString(
            localized: "\(modelsTotal) in ^[\(1) tool](inflect: true), none of it recommended."
        ).characters))
        #expect(words([]) == nil)
    }
}
