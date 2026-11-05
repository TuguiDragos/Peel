import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct OwnerChoicePlacesTests {
    private func app(at path: String) -> OwnerChoice {
        .app(InstalledApp(url: URL(filePath: path), bundleIdentifier: "org.example.tide", name: "Tide"))
    }

    @Test func aChoiceWhoseNameAnotherSharesSaysWhereItIs() {
        let formula = OwnerChoice.tool(HomebrewPackage(name: "jq", kind: .formula))
        let command = OwnerChoice.command(.init(name: "jq", url: URL(filePath: "/opt/local/bin/jq")))
        let tree = OwnerChoice.tool(HomebrewPackage(name: "tree", kind: .formula))
        let shown = [formula, command, tree, app(at: "/Applications/Tide.app")]
        #expect(OwnerChoice.places(whereNamesRepeat: shown) == [formula.id: "Homebrew", command.id: "/opt/local/bin"])
    }

    @Test func twoCopiesOfAnAppSayTheirFolders() {
        let one = app(at: "/Applications/Tide.app")
        let other = app(at: NSHomeDirectory() + "/Applications/Tide.app")
        let places = OwnerChoice.places(whereNamesRepeat: [one, other])
        #expect(places == [one.id: "/Applications", other.id: "~/Applications"])
    }
}
