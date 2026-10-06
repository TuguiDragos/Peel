import Foundation
@testable import PeelCore
import Testing

struct AppDevelopersTests {
    private func app(_ name: String, team: String? = nil, developer: String? = nil) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/\(name).app"), bundleIdentifier: "org.example.\(name.lowercased())",
            name: name, teamIdentifier: team, developer: developer
        )
    }

    @Test func namesAnAppFromItsSignatureThenItsTeamThenTheAppStore() {
        let signed = app("Studio", team: "ABCDE12345", developer: "Example Inc.")
        let storeCopy = app("Notes Plus", team: "ABCDE12345")
        let unsigned = app("Tool")
        let developers = AppDevelopers([signed, storeCopy, unsigned])

        #expect(developers.developer(of: signed, remembered: "Someone Else") == "Example Inc.")
        #expect(developers.developer(of: storeCopy, remembered: nil) == "Example Inc.")
        #expect(developers.developer(of: unsigned, remembered: "Tool Makers") == "Tool Makers")
        #expect(developers.developer(of: unsigned, remembered: nil) == nil)
    }

    @Test func offersTheDevelopersOfTwoOrMoreAppsAndTheOneChosen() {
        let names = ["Example Inc.", "zeta", "Example Inc.", "Alpha", "Alpha", "Solo"]

        #expect(AppDevelopers.offered(names, chosen: nil) == ["Alpha", "Example Inc."])
        #expect(AppDevelopers.offered(names, chosen: "Gone") == ["Alpha", "Example Inc.", "Gone"])
        #expect(AppDevelopers.offered(names, chosen: "Alpha") == ["Alpha", "Example Inc."])
    }
}
