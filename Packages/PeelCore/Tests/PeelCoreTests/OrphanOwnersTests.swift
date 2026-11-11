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
        #expect(owners.give("org.example.cmd", to: .command("mytool")) == .saved)

        let written = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(written["org.example.helper"] as? String == "com.installed.app")
        #expect(written["org.example.tool"] as? [String: String] == ["formula": "exampletool"])
        #expect(written["org.example.cmd"] as? [String: String] == ["command": "mytool"])
        #expect(owners.load()?["org.example.cmd"] == .command("mytool"))
    }

    @Test func leavesOutWhatBelongsToAnInstalledAppOrToolAndToAToolNotYetKnown() {
        let owners: [String: OrphanOwner] = [
            "org.example.given": .app("com.installed.app"), "org.example.gone": .app("org.example.notinstalled"),
            "org.example.tool": .formula("exampletool"), "org.example.lost": .formula("gonetool"),
            "org.example.cmd": .command("mytool"), "org.example.nocmd": .command("gone"),
        ]
        let apps: Set<String> = ["com.installed.app"]

        #expect(
            OrphanOwners.given(owners, apps: apps, tools: InstalledTools(formulae: ["exampletool"], commands: ["mytool"]))
                == ["org.example.given", "org.example.tool", "org.example.cmd"]
        )
        #expect(
            OrphanOwners.given(owners, apps: apps, tools: InstalledTools(formulae: [], commands: []))
                == ["org.example.given"]
        )
        #expect(
            OrphanOwners.given(owners, apps: apps, tools: .notKnown)
                == ["org.example.given", "org.example.tool", "org.example.lost", "org.example.cmd", "org.example.nocmd"]
        )
    }

    @Test func anOwnerThisVersionDoesNotKnowCostsOnlyItsOwnGroup() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file(
            "Peel/orphan-owners.json",
            contents: Data(#"{"org.example.group":"org.example.owner","org.example.other":{"kindFromLater":"x"}}"#.utf8)
        )

        #expect(OrphanOwners(url: file).load() == ["org.example.group": .app("org.example.owner")])
    }

    @Test func aChangeKeepsWhatThisVersionDoesNotKnowAsItWas() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file(
            "Peel/orphan-owners.json", contents: Data(#"{"org.example.other":{"kindFromLater":"x"}}"#.utf8)
        )

        #expect(OrphanOwners(url: file).give("org.example.group", to: .formula("mole")) == .saved)

        let written = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect((written["org.example.other"] as? [String: String]) == ["kindFromLater": "x"])
        #expect((written["org.example.group"] as? [String: String]) == ["formula": "mole"])
    }
}
