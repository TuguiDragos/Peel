import ArgumentParser
import Foundation
import PeelCore

struct ExclusionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exclusions",
        abstract: "Show and change what Peel leaves alone.",
        discussion: "The same list the Peel app keeps. Nothing excluded is scanned, offered, or moved by either.",
        subcommands: [ListCommand.self, AddCommand.self, RemoveCommand.self],
        defaultSubcommand: ListCommand.self
    )

    /// Returns the saved exclusions, or throws when the file exists but can't be read. Saving would set that
    /// file aside and silently drop what the user chose. Only the app starts a new list, after warning the user.
    static func current(in store: ExclusionStore) async throws -> Exclusions {
        let exclusions = await store.load()
        guard !exclusions.isUnreadable else {
            throw CommandFailure("Peel couldn't read its exclusions file, so it won't change it. Open Peel and click Start Over in Settings > Exclusions.")
        }
        return exclusions
    }

    /// Returns the bundle identifier of `app`, found by path, bundle identifier, or name, as the other commands do.
    static func identifier(of app: String, among apps: [InstalledApp]? = nil) async throws -> String {
        let installed = if let apps { apps } else { await AppCatalog.installedApps() }
        return try AppLookup.app(matching: app, in: installed).bundleIdentifier
    }

    static func save(_ exclusions: Exclusions, in store: ExclusionStore) async throws {
        guard await store.save(exclusions) else {
            throw CommandFailure("Peel couldn't write its exclusions, so nothing changed.")
        }
    }

    struct ListCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Show what Peel leaves alone.")

        @OptionGroup var output: OutputOptions

        private struct Record: Encodable {
            let paths: [String]
            let apps: [String]
        }

        func run() async throws {
            try await run(in: ExclusionStore())
        }

        func run(in store: ExclusionStore) async throws {
            let exclusions = try await ExclusionsCommand.current(in: store)
            let paths = exclusions.paths.map(Output.path).sorted()
            let apps = exclusions.bundleIdentifiers.sorted()

            if output.json {
                try Output.json(Record(paths: paths, apps: apps))
            } else if exclusions.isEmpty {
                Output.line("Peel isn't leaving anything alone.")
            } else {
                Output.table(Self.rows(for: exclusions))
            }
        }

        static func rows(for exclusions: Exclusions) -> [[String]] {
            exclusions.paths.map(Output.path).sorted().map { ["path", $0] }
                + exclusions.bundleIdentifiers.sorted().map { ["app", $0] }
        }
    }

    struct AddCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Leave a file, a folder, or an app alone.",
            discussion: "A whole disk, a home folder, or a Library is refused: excluding one would leave every tool with nothing to show."
        )

        @Argument(help: "Files or folders to leave alone.", completion: .file())
        var paths: [String] = []

        @Option(help: "An app to leave alone: its path, bundle identifier, or name.")
        var app: String?

        func validate() throws {
            guard !paths.isEmpty || app != nil else {
                throw ValidationError("Give a path, or --app.")
            }
            let broad = paths.map(URL.init(argument:)).filter { Exclusions.isTooBroad($0) }
            guard broad.isEmpty else {
                throw ValidationError("\(broad.map(Output.path).joined(separator: ", ")): too broad to exclude. Name a folder inside it.")
            }
        }

        func run() async throws {
            try await run(in: ExclusionStore())
        }

        func run(in store: ExclusionStore, among apps: [InstalledApp]? = nil) async throws {
            var exclusions = try await ExclusionsCommand.current(in: store)
            exclusions.paths.formUnion(paths.map { URL(argument: $0).standardizedFileURL })
            if let app {
                exclusions.bundleIdentifiers.insert(try await ExclusionsCommand.identifier(of: app, among: apps))
            }
            try await ExclusionsCommand.save(exclusions, in: store)
            Output.line("Peel will leave \(Output.count(paths.count + (app == nil ? 0 : 1), "item", "items")) alone.")
        }
    }

    struct RemoveCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "Stop leaving something alone.")

        @Argument(help: "Files or folders to stop leaving alone.", completion: .file())
        var paths: [String] = []

        @Option(help: "An app to stop leaving alone: its path, bundle identifier, or name.")
        var app: String?

        func validate() throws {
            guard !paths.isEmpty || app != nil else {
                throw ValidationError("Give a path, or --app.")
            }
        }

        func run() async throws {
            try await run(in: ExclusionStore())
        }

        func run(in store: ExclusionStore, among apps: [InstalledApp]? = nil) async throws {
            var exclusions = try await ExclusionsCommand.current(in: store)
            let before = exclusions
            exclusions.paths.subtract(paths.map { URL(argument: $0).standardizedFileURL })
            // First removes `app` exactly as written, so an app that isn't installed can still come off the
            // list. Only when that took off no app is `app` looked up among the installed apps.
            if let app {
                exclusions.bundleIdentifiers.remove(app)
                if exclusions.bundleIdentifiers == before.bundleIdentifiers, let identifier = try? await ExclusionsCommand.identifier(of: app, among: apps) {
                    exclusions.bundleIdentifiers.remove(identifier)
                }
            }
            guard exclusions != before else {
                throw CommandFailure("Peel wasn't leaving that alone. See `peel exclusions list`.")
            }
            try await ExclusionsCommand.save(exclusions, in: store)
            Output.line("Peel will treat it like anything else again.")
        }
    }
}
