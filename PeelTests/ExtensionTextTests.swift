import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct ExtensionTextTests {
    private func part(name: String, owner: String?, point: String?) -> AppExtension {
        AppExtension(
            identifier: "org.example.app.part", name: name, kind: .appExtension, point: point, owner: owner,
            url: URL(filePath: "/Applications/Example.app/Contents/PlugIns/Part.appex"), election: .on,
            teamIdentifier: nil, reportedState: nil
        )
    }

    @Test func aRowNamedLikeItsAppSaysWhatItPlugsInto() throws {
        let widget = part(name: "Example", owner: "Example", point: "com.apple.widgetkit-extension")
        let share = part(name: "Example", owner: "Example", point: "com.apple.share-services")

        #expect(widget.rowDetail == widget.pointName)
        #expect(widget.rowDetail != share.rowDetail, "two parts of one app read apart")
        #expect(part(name: "Example Widget", owner: "Example", point: "com.apple.widgetkit-extension").rowDetail == "Example")
        #expect(part(name: "Example", owner: nil, point: "com.apple.FinderSync").rowDetail == part(
            name: "Example", owner: nil, point: "com.apple.FinderSync"
        ).pointName)
    }

    @Test func findsAPartByTheWordItsPageShows() throws {
        let widget = part(name: "Example", owner: "Example", point: "com.apple.widgetkit-extension")
        let word = try #require(widget.pointName)

        #expect(widget.matches(word))
        #expect(!part(name: "Example", owner: "Example", point: "com.apple.share-services").matches(word))
    }
}
