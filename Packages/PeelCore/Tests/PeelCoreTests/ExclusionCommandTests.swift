import ArgumentParser
import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

/// Tests `peel exclusions`, which edits the same list the removal guard reads.
struct ExclusionCommandTests {
    private let editor = InstalledApp(
        url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory),
        bundleIdentifier: "com.example.editor",
        name: "Editor"
    )

    private func store(in directory: borrowing TemporaryDirectory) -> ExclusionStore {
        ExclusionStore(url: directory.url.appending(path: "Peel/exclusions.json"))
    }

    /// Parses `arguments` the way a shell passes them, so the flags and the work are tested together.
    private func command<Command: AsyncParsableCommand>(_ arguments: [String]) throws -> Command {
        try #require(try PeelCommand.parseAsRoot(arguments) as? Command)
    }

    private func add(_ arguments: [String], in store: ExclusionStore, among apps: [InstalledApp]? = nil) async throws {
        try await (command(["exclusions", "add"] + arguments) as ExclusionsCommand.AddCommand).run(in: store, among: apps)
    }

    private func remove(_ arguments: [String], in store: ExclusionStore, among apps: [InstalledApp]? = nil) async throws {
        try await (command(["exclusions", "remove"] + arguments) as ExclusionsCommand.RemoveCommand).run(in: store, among: apps)
    }

    private func list(_ arguments: [String] = [], in store: ExclusionStore) async throws {
        try await (command(["exclusions", "list"] + arguments) as ExclusionsCommand.ListCommand).run(in: store)
    }

    private func saved(_ store: ExclusionStore) async -> Exclusions {
        await ExclusionStore(url: store.url).load()
    }

    @Test func addsAPathAndWritesItDown() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)
        let folder = try directory.directory("home/Documents/Keep")

        try await add([folder.path(percentEncoded: false)], in: store)

        #expect(await saved(store).paths == [folder])
        #expect(await saved(store).excludes(folder.appending(path: "inside.txt")))
    }

    /// `--app Editor` reaches the same app every other command would, and the list keeps its identifier.
    @Test func addsAnAppByNameAndKeepsItsIdentifier() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)

        try await add(["--app", "Editor"], in: store, among: [editor])

        #expect(await saved(store).bundleIdentifiers == ["com.example.editor"])
        #expect(await saved(store).excludes(editor))
    }

    @Test func refusesAnAppItCannotFind() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)

        await #expect(throws: AppLookup.Failure.notFound("Missing")) {
            try await add(["--app", "Missing"], in: store, among: [editor])
        }
        #expect(await saved(store).isEmpty)
    }

    @Test func removesAPath() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)
        let folder = try directory.directory("home/Documents/Keep")
        try await add([folder.path(percentEncoded: false)], in: store)

        try await remove([folder.path(percentEncoded: false)], in: store)

        #expect(await saved(store).isEmpty)
    }

    /// An app that is not installed stays in the list, so it can be removed by the identifier saved there.
    @Test func removesAnAppThatIsNoLongerInstalled() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)
        try await add(["--app", "Editor"], in: store, among: [editor])

        try await remove(["--app", "com.example.editor"], in: store, among: [])

        #expect(await saved(store).isEmpty)
    }

    @Test func removesAnAppByNameWhileItIsStillInstalled() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)
        try await add(["--app", "Editor"], in: store, among: [editor])

        try await remove(["--app", "Editor"], in: store, among: [editor])

        #expect(await saved(store).isEmpty)
    }

    /// A path and an app in one command are two removals: taking the path off the list must not keep the app,
    /// named as the user knows it, from being looked up and taken off too.
    @Test func removesAnAppByNameAlongWithAPath() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)
        let folder = try directory.directory("Projects").path(percentEncoded: false)
        try await add([folder, "--app", "Editor"], in: store, among: [editor])

        try await remove([folder, "--app", "Editor"], in: store, among: [editor])

        #expect(await saved(store).isEmpty, "the app stayed excluded while the command said it was not")
    }

    @Test func refusesToRemoveWhatWasNotThere() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)

        await #expect(throws: CommandFailure.self) {
            try await remove(["/Users/me/nothing"], in: store)
        }
    }

    /// While the saved list cannot be read, every subcommand refuses, and the file is never written over: it
    /// holds what the user chose.
    @Test func refusesEveryChangeWhileTheListCannotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)
        try directory.file("Peel/exclusions.json", contents: Data("not json".utf8))

        await #expect(throws: CommandFailure.self) {
            try await add(["/Users/me/thing"], in: store)
        }
        await #expect(throws: CommandFailure.self) {
            try await remove(["/Users/me/thing"], in: store)
        }
        await #expect(throws: CommandFailure.self) {
            try await list(in: store)
        }
        #expect(try Data(contentsOf: store.url) == Data("not json".utf8))
    }

    @Test func saysSoWhenItCannotWrite() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Peel")
        let store = store(in: directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false)) }

        await #expect(throws: CommandFailure.self) {
            try await add(["/Users/me/thing"], in: store)
        }
    }

    /// The listing has one row per item, paths before apps, each path written in full without a trailing slash.
    @Test func writesARowPerItemItLeavesAlone() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)
        try await add(["/Users/me/Documents/Keep/", "/Users/me/a.txt", "--app", "Editor"], in: store, among: [editor])

        let rows = ExclusionsCommand.ListCommand.rows(for: await saved(store))

        #expect(rows == [
            ["path", "/Users/me/Documents/Keep"],
            ["path", "/Users/me/a.txt"],
            ["app", "com.example.editor"],
        ])
    }

    @Test func leavingNothingAloneIsASentenceAndAnEmptyList() async throws {
        let directory = try TemporaryDirectory()
        let store = store(in: directory)

        #expect(ExclusionsCommand.ListCommand.rows(for: .none).isEmpty)
        try await list(in: store)
        try await list(["--json"], in: store)
        #expect(await saved(store).isEmpty)
    }

    /// Excluding a whole disk, a home folder, or a Library would leave every tool with nothing to show.
    @Test func refusesWhatIsTooBroadBeforeItRuns() throws {
        for path in ["/", "/Applications", "/Library", "/Users", NSHomeDirectory(), NSHomeDirectory() + "/Library"] {
            #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["exclusions", "add", path]) }
        }
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["exclusions", "add"]) }
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["exclusions", "remove"]) }
        #expect(try PeelCommand.parseAsRoot(["exclusions", "add", NSHomeDirectory() + "/Documents/Keep"]) is ExclusionsCommand.AddCommand)
    }
}
