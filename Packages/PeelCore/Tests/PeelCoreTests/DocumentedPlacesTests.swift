import Foundation
@testable import PeelCore
import Testing

struct DocumentedPlacesTests {
    private struct MakersApp: ~Copyable {
        let directory: TemporaryDirectory
        let app: InstalledApp
        let environment: SearchEnvironment

        init(identifier: String = "com.nomachine.nxdock", name: String = "NoMachine") throws {
            let directory = try TemporaryDirectory()
            self.app = InstalledApp(
                url: try directory.directory("root/Applications/\(name).app"), bundleIdentifier: identifier, name: name
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
        let noMachine = try MakersApp()
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
        let unused = try MakersApp()
        try unused.directory.file("home/.nx/workspace-data/lock")
        let another = try MakersApp(identifier: "org.example.remote")
        try another.directory.file("home/.nx/config/player.cfg")
        try another.directory.file("home/Documents/NoMachine/Office.nxs")

        #expect(await unused.rows()[unused.path("home/.nx")] == nil)
        let rows = await another.rows()
        #expect(rows[another.path("home/.nx")] == nil)
        #expect(rows[another.path("home/Documents/NoMachine")] == nil)
    }

    @Test func holdsBackOllamasFolderForTheModelsInside() async throws {
        let ollama = try MakersApp(identifier: "com.electron.ollama", name: "Ollama")
        try ollama.directory.file("home/.ollama/models/blobs/sha256-1a2b", bytes: 4_096)
        try ollama.directory.file("home/.ollama/history")

        let row = try #require(await ollama.rows()[ollama.path("home/.ollama")])

        #expect(row.match.heldBack == .holdsModels)
        #expect(!row.match.isRecommended)
    }

    @Test func listsOsaurusModelsAndChatsAndSelectsNeither() async throws {
        let osaurus = try MakersApp(identifier: "com.dinoki.osaurus", name: "Osaurus")
        try osaurus.directory.file("home/MLXModels/mlx-community/Qwen3-4B-4bit/model.safetensors", bytes: 4_096)
        try osaurus.directory.file("home/.osaurus/chats.sqlite")

        let rows = await osaurus.rows()

        let models = try #require(rows[osaurus.path("home/MLXModels")])
        #expect(models.match.reason == .documentedByItsMaker)
        #expect(models.match.heldBack == .holdsModels)
        let chats = try #require(rows[osaurus.path("home/.osaurus")])
        #expect(chats.match.heldBack == .holdsWorkMadeWithTheApp)
        #expect(!models.match.isRecommended && !chats.match.isRecommended)
    }
}
