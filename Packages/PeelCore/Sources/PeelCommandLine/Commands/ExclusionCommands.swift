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
        guard !exclusions.isUnreadable else { throw CommandFailure(unreadable) }
        return exclusions
    }

    private static let unreadable = "Peel couldn't read its exclusions file, so it won't change it. Open Peel and click Start Over in Settings > Exclusions."

    /// Returns the bundle identifier of `app`, found by path, bundle identifier, or name, as the other commands do.
    static func identifier(of app: String, among apps: [InstalledApp]? = nil) async throws -> String {
        let installed = if let apps { apps } else { await AppCatalog.installedApps() }
        return try AppLookup.app(matching: app, in: installed).bundleIdentifier
    }

    /// Changes the saved list with `transform`, read again and written under the file's lock, so what the app or
    /// another command saved meanwhile is kept.
    static func change(in store: ExclusionStore, _ transform: @Sendable (inout Exclusions) -> Void) async throws {
        switch await store.change(transform) {
        case .saved:
            return
        case .unreadable:
            throw CommandFailure(unreadable)
        case .notSaved:
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

        @Option(help: "An app to leave alone: its path, bundle identifier, or name. Write ./Name.app for a bundle in the current folder.")
        var app: String?

        func validate() throws {
            guard !paths.isEmpty || app != nil else {
                throw ValidationError("Give a path, or --app.")
            }
            let broad = paths.map(URL.init(argument:)).filter { Exclusions.isTooBroad($0) }
            guard broad.isEmpty else {
                throw ValidationError("\(broad.map { Output.plain(Output.path($0)) }.joined(separator: ", ")): too broad to exclude. Name a folder inside it.")
            }
        }

        func run() async throws {
            try await run(in: ExclusionStore())
        }

        func run(in store: ExclusionStore, among apps: [InstalledApp]? = nil) async throws {
            _ = try await ExclusionsCommand.current(in: store)
            // The app is looked up before the list is changed, since looking it up can take a while.
            var identifier: String?
            if let app {
                identifier = try await ExclusionsCommand.identifier(of: app, among: apps)
            }
            let added = paths.map(URL.init(argument:))
            try await ExclusionsCommand.change(in: store) { [identifier] exclusions in
                exclusions.add(added)
                if let identifier { exclusions.bundleIdentifiers.insert(identifier) }
            }
            Output.line("Peel will leave \(Output.count(paths.count + (app == nil ? 0 : 1), "item", "items")) alone.")
        }
    }

    struct RemoveCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "Stop leaving something alone.")

        @Argument(help: "Files or folders to stop leaving alone.", completion: .file())
        var paths: [String] = []

        @Option(help: "An app to stop leaving alone: its path, bundle identifier, or name. Write ./Name.app for a bundle in the current folder.")
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
            let before = try await ExclusionsCommand.current(in: store)
            let removed = paths.map(URL.init(argument:))
            // `app` comes off exactly as written, so an app that isn't installed can still come off the list. Only
            // when the list has no such identifier is `app` looked up among the installed apps.
            var identifiers: Set<String> = []
            if let app {
                if before.bundleIdentifiers.contains(app) {
                    identifiers.insert(app)
                } else if let identifier = try? await ExclusionsCommand.identifier(of: app, among: apps) {
                    identifiers.insert(identifier)
                }
            }
            var remaining = before
            guard remaining.remove(removed) || !before.bundleIdentifiers.isDisjoint(with: identifiers) else {
                throw CommandFailure("Peel wasn't leaving that alone. See `peel exclusions list`.")
            }
            try await ExclusionsCommand.change(in: store) { [identifiers] exclusions in
                exclusions.remove(removed)
                exclusions.bundleIdentifiers.subtract(identifiers)
            }
            Output.line("Peel will treat it like anything else again.")
        }
    }
}
