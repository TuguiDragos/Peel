import ArgumentParser
import Foundation
import PeelCore

struct ExclusionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exclusions",
        abstract: "Show and change what Peel leaves alone.",
        discussion: "The same list the Peel app keeps. Nothing excluded is offered or moved by either, though an excluded app is still listed. Without a subcommand, it shows the list.",
        subcommands: [ListCommand.self, AddCommand.self, RemoveCommand.self],
        defaultSubcommand: ListCommand.self
    )

    /// Returns the saved exclusions, or throws when the file exists but can't be read. Saving would set that
    /// file aside and silently drop what the user chose. Only the app starts a new list, after warning the user.
    static func current(in store: ExclusionStore, whenUnreadable said: String = unreadable) async throws -> Exclusions {
        let exclusions = await store.load()
        guard !exclusions.isUnreadable else { throw CommandFailure(said + exclusions.whyUnreadable.sentence) }
        return exclusions
    }

    private static let unreadable = "Peel couldn't read its exclusions file, so it won't change it. Open Peel and click Start Over in Settings > Exclusions."

    /// Returns the app `query` names, found by path, bundle identifier, or name, as the other commands do.
    static func app(_ query: String, among apps: [InstalledApp]? = nil) async throws -> InstalledApp {
        let installed = if let apps { apps } else { await AppCatalog.installedApps() }
        return try AppLookup.app(matching: query, in: installed)
    }

    /// Changes the saved list with `transform`, read again and written under the file's lock, so what the app or
    /// another command saved meanwhile is kept.
    static func change(in store: ExclusionStore, _ transform: @Sendable (inout Exclusions) -> Void) async throws {
        switch await store.change(transform) {
        case .saved:
            return
        case .unreadable(let why):
            throw CommandFailure(unreadable + why.sentence)
        case .notSaved(_, let why):
            throw CommandFailure("Peel couldn't write its exclusions, so nothing changed." + why.sentence)
        }
    }

    struct ListCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Show what Peel leaves alone.")

        @OptionGroup var output: OutputOptions

        private struct Record: Encodable {
            let paths: [String]
            let apps: [String]
            let unreadableEntries: Int
        }

        func run() async throws {
            try await run(in: ExclusionStore())
        }

        func run(in store: ExclusionStore) async throws {
            let exclusions = try await ExclusionsCommand.current(
                in: store,
                whenUnreadable: "Peel couldn't read its exclusions file, so it can't say what it leaves alone. Open Peel and click Start Over in Settings > Exclusions."
            )
            let paths = exclusions.paths.map(Output.path).sorted()
            let apps = exclusions.bundleIdentifiers.sorted()

            if exclusions.unreadableEntries > 0 {
                let count = exclusions.unreadableEntries
                Output.note("Peel couldn't read \(Output.count(count, "entry", "entries")) in its exclusions file, so what \(count == 1 ? "it names isn't" : "they name aren't") left alone. The file is kept aside as it is the next time the list changes.")
            }
            if output.json {
                try Output.json(Record(paths: paths, apps: apps, unreadableEntries: exclusions.unreadableEntries))
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
            discussion: "The startup disk, a folder at its top, your home folder, or its Library is refused: excluding one would leave every tool with nothing to show."
        )

        @Argument(help: "Files or folders to leave alone.", completion: .file())
        var paths: [String] = []

        @Option(help: "An app to leave alone: its path, bundle identifier, or name. Write ./Name.app for a bundle in the current folder.")
        var app: String?

        func validate() throws {
            guard !paths.isEmpty || app != nil else {
                throw ValidationError("Give a path, or --app.")
            }
            try refuseEmptyPaths(paths)
            let broad = paths.map(URL.init(argument:)).filter { Exclusions.isTooBroad($0) }
            guard broad.isEmpty else {
                throw ValidationError("\(broad.map { Output.plain(Output.path($0)) }.joined(separator: ", ")): too broad to exclude. Name a folder inside it.")
            }
        }

        func run() async throws {
            try await run(in: ExclusionStore())
        }

        func run(in store: ExclusionStore, among apps: [InstalledApp]? = nil) async throws {
            let current = try await ExclusionsCommand.current(in: store)
            // The app is looked up before the list is changed, since looking it up can take a while.
            // An app with no identifier is left alone by where it is.
            var identifier: String?
            var added = paths.map(URL.init(argument:))
            if let app {
                let installed = if let apps { apps } else { await AppCatalog.installedApps() }
                // An identifier leaves every copy alone, so two copies that share one need no choice between them.
                if let shared = installed.lazy.compactMap(\.bundleIdentifier)
                    .first(where: { $0.caseInsensitiveCompare(app) == .orderedSame }) {
                    identifier = shared
                } else {
                    let found = try await ExclusionsCommand.app(app, among: installed)
                    if let found = found.bundleIdentifier { identifier = found } else { added.append(found.url) }
                }
            }
            for url in added where url.isMissing {
                Output.note("\(Output.plain(Output.path(url))) isn't there yet. Peel will leave it alone once it is.")
            }
            var after = current
            var placesOn: [URL] = []
            for url in added where !after.lists(url) {
                after.add([url])
                placesOn.append(url)
            }
            let identifierOn = identifier.flatMap { current.bundleIdentifiers.contains($0) ? nil : $0 }
            let names = (placesOn.map(Output.path) + [identifierOn].compactMap(\.self)).map(Output.plain)
            try await ExclusionsCommand.change(in: store) { [identifier, added] exclusions in
                exclusions.add(added)
                if let identifier { exclusions.bundleIdentifiers.insert(identifier) }
            }
            Output.line(names.isEmpty ? "Peel was already leaving that alone." : "Peel will leave \(names.joined(separator: ", ")) alone.")
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
            try refuseEmptyPaths(paths)
        }

        func run() async throws {
            try await run(in: ExclusionStore())
        }

        func run(in store: ExclusionStore, among apps: [InstalledApp]? = nil) async throws {
            let before = try await ExclusionsCommand.current(in: store)
            var removed = paths.map(URL.init(argument:))
            // `app` is looked for on the list first, in any capitals, since `add` writes what the app itself declares,
            // so an app that isn't installed can still come off. Only then is it looked up among the installed apps.
            var identifiers = before.bundleIdentifiers.filter { $0.caseInsensitiveCompare(app ?? "") == .orderedSame }
            if let app, identifiers.isEmpty, let found = try? await ExclusionsCommand.app(app, among: apps) {
                if let identifier = found.bundleIdentifier {
                    identifiers.insert(identifier)
                } else {
                    removed.append(found.url)
                }
            }
            let placesOff = removed.filter(before.lists)
            let identifiersOff = before.bundleIdentifiers.intersection(identifiers)
            guard !placesOff.isEmpty || !identifiersOff.isEmpty else {
                // What is inside a folder on the list stays alone until the folder comes off.
                if let url = removed.first(where: { !before.reasons(excluding: $0, app: nil).folders.isEmpty }) {
                    throw CommandFailure(Self.notOnTheList(url, in: before))
                }
                throw CommandFailure("Peel wasn't leaving that alone. See `peel exclusions list`.")
            }
            try await ExclusionsCommand.change(in: store) { [identifiers, removed] exclusions in
                exclusions.remove(removed)
                exclusions.bundleIdentifiers.subtract(identifiers)
            }
            var missed = removed.filter { !before.lists($0) }.map { Self.notOnTheList($0, in: before) }
            if let app, identifiersOff.isEmpty, removed.count == paths.count {
                missed.append("Peel wasn't leaving \(Output.plain(app)) alone.")
            }
            let names = (placesOff.map(Output.path) + identifiersOff.sorted()).map(Output.plain)
            let what = missed.isEmpty ? (names.count == 1 ? "it" : "them") : names.joined(separator: ", ")
            Output.line("Peel will treat \(what) like anything else again.")
            missed.forEach(Output.note)
        }

        private static func notOnTheList(_ url: URL, in exclusions: Exclusions) -> String {
            let place = Output.plain(Output.path(url))
            guard let folder = exclusions.reasons(excluding: url, app: nil).folders.first else {
                return "Peel wasn't leaving \(place) alone."
            }
            return "Peel leaves \(place) alone because it is inside \(Output.plain(Output.path(folder))), which is on the list. Remove that instead."
        }
    }
}
