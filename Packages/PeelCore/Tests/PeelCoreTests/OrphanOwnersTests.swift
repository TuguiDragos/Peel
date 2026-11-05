import Foundation
@testable import PeelCore
import Testing

struct OrphanOwnersTests {
    @Test func readsAListWrittenBeforeAToolCouldBeNamed() throws {
        let directory = try TemporaryDirectory()
        try directory.file("orphan-owners.json", contents: Data(#"{"org.example.helper":"com.installed.app"}"#.utf8))

        let owners = OrphanOwners(url: directory.url.appending(path: "orphan-owners.json"))

        #expect(owners.load() == ["org.example.helper": .app("com.installed.app")])
    }

    @Test func writesAnAppAsBeforeAndAToolUnderItsOwnKey() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "orphan-owners.json")
        let owners = OrphanOwners(url: url)

        #expect(owners.give("org.example.helper", to: .app("com.installed.app")) == .saved)
        #expect(owners.give("org.example.tool", to: .formula("exampletool")) == .saved)

        let written = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(written["org.example.helper"] as? String == "com.installed.app")
        #expect(written["org.example.tool"] as? [String: String] == ["formula": "exampletool"])
    }

    @Test func leavesOutWhatBelongsToAnInstalledAppOrToolAndToAToolNotYetKnown() {
        let owners: [String: OrphanOwner] = [
            "org.example.given": .app("com.installed.app"), "org.example.gone": .app("org.example.notinstalled"),
            "org.example.tool": .formula("exampletool"), "org.example.lost": .formula("gonetool"),
        ]
        let apps: Set<String> = ["com.installed.app"]

        #expect(OrphanOwners.given(owners, apps: apps, formulae: ["exampletool"]) == ["org.example.given", "org.example.tool"])
        #expect(OrphanOwners.given(owners, apps: apps, formulae: []) == ["org.example.given"])
        #expect(
            OrphanOwners.given(owners, apps: apps, formulae: nil)
                == ["org.example.given", "org.example.tool", "org.example.lost"]
        )
    }
}
