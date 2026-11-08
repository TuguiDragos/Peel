import Foundation
@testable import PeelCore
import Testing

struct DocumentedPlacesTests {
    private struct NoMachine: ~Copyable {
        let directory: TemporaryDirectory
        let app: InstalledApp
        let environment: SearchEnvironment

        init(identifier: String = "com.nomachine.nxdock") throws {
            let directory = try TemporaryDirectory()
            self.app = InstalledApp(
                url: try directory.directory("root/Applications/NoMachine.app"), bundleIdentifier: identifier,
                name: "NoMachine"
            )
            self.environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
            self.directory = directory
        }

        func rows() async -> [String: Leftover] {
            let plan = await Uninstallation.prepare(app, installedApps: [app], environment: environment)
            return Dictionary(
                plan.scan.leftovers.map { (PathPattern.comparablePath(of: $0.url), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        func path(_ relative: String) -> String {
            PathPattern.comparablePath(of: directory.url.appending(path: relative))
        }
    }

    @Test func listsNoMachinesConnectionsAndFavoritesAndSelectsNeither() async throws {
        let noMachine = try NoMachine()
        try noMachine.directory.file("home/.nx/config/player.cfg")
        try noMachine.directory.file("home/Documents/NoMachine/Office.nxs")

        let rows = await noMachine.rows()

        for place in ["home/.nx", "home/Documents/NoMachine"] {
            let row = try #require(rows[noMachine.path(place)], "\(place)")
            #expect(row.match.reason == .documentedByItsMaker)
            #expect(row.match.confidence == .certain)
            #expect(row.match.heldBack == .holdsWorkMadeWithTheApp)
            #expect(!row.match.isRecommended)
        }
    }

    @Test func leavesWhatItsMakerDoesntDocumentOrAnotherAppKeeps() async throws {
        let unused = try NoMachine()
        try unused.directory.file("home/.nx/workspace-data/lock")
        let another = try NoMachine(identifier: "org.example.remote")
        try another.directory.file("home/.nx/config/player.cfg")
        try another.directory.file("home/Documents/NoMachine/Office.nxs")

        #expect(await unused.rows()[unused.path("home/.nx")] == nil)
        let rows = await another.rows()
        #expect(rows[another.path("home/.nx")] == nil)
        #expect(rows[another.path("home/Documents/NoMachine")] == nil)
    }
}
