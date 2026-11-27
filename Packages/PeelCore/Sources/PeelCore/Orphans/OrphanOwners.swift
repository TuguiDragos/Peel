public import Foundation
internal import PeelPrivileged

/// What a group of orphaned files belongs to, as the person said: an app, by its bundle identifier, or by its place
/// when it has none; a formula Homebrew installed; or a command in the tool folders, by its place, or by its name
/// alone when it was chosen before Peel kept the place.
public enum OrphanOwner: Sendable, Hashable {
    case app(String)
    case appWithNoIdentifier(at: URL)
    case formula(String)
    case command(String, at: URL? = nil)
}

extension OrphanOwner: Codable {
    private enum CodingKeys: String, CodingKey {
        case app
        case formula
        case command
        case at
    }

    /// An app is written as its bundle identifier alone, as every list written before tools could be named, and an
    /// app with no identifier, a formula, or a command under its own key.
    public init(from decoder: any Decoder) throws {
        if let identifier = try? decoder.singleValueContainer().decode(String.self) {
            self = .app(identifier)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let place = try container.decodeIfPresent(String.self, forKey: .app) {
            self = .appWithNoIdentifier(at: URL(filePath: place))
        } else if let name = try container.decodeIfPresent(String.self, forKey: .formula) {
            self = .formula(name)
        } else {
            self = .command(
                try container.decode(String.self, forKey: .command),
                at: try container.decodeIfPresent(String.self, forKey: .at).map { URL(filePath: $0) }
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .app(let identifier):
            var container = encoder.singleValueContainer()
            try container.encode(identifier)
        case .appWithNoIdentifier(let place):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(place.path(percentEncoded: false), forKey: .app)
        case .formula(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .formula)
        case .command(let name, let place):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .command)
            try container.encodeIfPresent(place?.path(percentEncoded: false), forKey: .at)
        }
    }
}

/// What is installed on this Mac that a group of orphaned files can belong to besides an app: Homebrew's formulae and
/// the commands in the tool folders. A kind that isn't known is nil, and a group given to one of it stays out.
public struct InstalledTools: Sendable {
    public var formulae: Set<String>?
    public var commands: Set<String>?
    /// Where each command is in the tool folders, as `PathPattern.comparablePath` writes it.
    public var commandPlaces: Set<String>?
    /// The commands a person may name, for a chooser.
    public var offeredCommands: [CommandLineTools.Command]

    public init(
        formulae: Set<String>? = nil, commands: Set<String>? = nil, commandPlaces: Set<String>? = nil,
        offeredCommands: [CommandLineTools.Command] = []
    ) {
        self.formulae = formulae
        self.commands = commands
        self.commandPlaces = commandPlaces
        self.offeredCommands = offeredCommands
    }

    public static let notKnown = InstalledTools()

    /// What is installed now, read right before a scan: Homebrew's Cellar, asked once, gives its formulae and keeps
    /// its linked commands out of those offered.
    @concurrent
    public static func read(environment: SearchEnvironment = .current) async -> InstalledTools {
        let answers = Homebrew.Answers()
        let cellar = await Homebrew.cellar(asking: answers)
        let formulae = await Homebrew.installedFormulae(asking: answers)
        let commands = CommandLineTools.read(environment: environment, cellar: cellar)
        return InstalledTools(
            formulae: formulae, commands: commands?.names, commandPlaces: commands?.places,
            offeredCommands: commands?.offered ?? []
        )
    }
}

/// The orphaned files the person said belong to an app or a command-line tool, by the identifier of their group, so
/// Orphaned Files stops listing them while that app or tool is installed. It only ever takes rows out of the list:
/// nothing is moved.
public struct OrphanOwners: Sendable {
    public let url: URL

    public init(url: URL = OrphanOwners.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        PeelFolder.url.appending(path: "orphan-owners.json")
    }

    /// Each group's identifier, lowercased, and what it belongs to: none while the file isn't there, and nil when it is
    /// there and can't be read, which lists those groups again.
    public func load() -> [String: OrphanOwner]? {
        // Taking the lock makes its file and folder, and a read must leave a home as it found it.
        guard !url.isMissing else { return [:] }
        return FileLock.whileHeld(beside: url) { read() }
    }

    /// Why the list can't be read, asked again once `load()` found it couldn't: nil when it can, or isn't there.
    public func whyUnreadable() -> FileProblem? {
        guard !url.isMissing else { return nil }
        return FileLock.whileHeld(beside: url) { readProblem() }
    }

    /// Sets a list that cannot be read aside, under another name, so the person can say again what belongs to what.
    @discardableResult
    public func startOver() -> StartOver {
        FileLock.whileHeld(beside: url) {
            guard !url.isMissing, read() == nil else { return .notNeeded }
            return .settingAside(url)
        }
    }

    @discardableResult
    public func give(_ group: String, to owner: OrphanOwner) -> ListChange {
        change { $0[group.lowercased()] = owner }
    }

    /// Forgets what each of `groups` belongs to, so they are listed again.
    @discardableResult
    public func take(_ groups: [String]) -> ListChange {
        change { owners in groups.forEach { owners[$0.lowercased()] = nil } }
    }

    /// The groups, lowercased, whose owner is on this Mac: an app among `installedApps`, or a formula or a command
    /// among `tools`, an app or a command chosen where it is only while it is still there. While a kind of tool isn't
    /// known, every group given to one stays out, since the person's word stands until Peel knows better.
    public static func given(
        _ owners: [String: OrphanOwner], installedApps: [InstalledApp], tools: InstalledTools
    ) -> Set<String> {
        let identifiers = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() })
        let places = Set(installedApps.map { PathPattern.comparablePath(of: $0.url) })
        return Set(
            owners.filter { _, owner in
                switch owner {
                case .app(let identifier): identifiers.contains(identifier.lowercased())
                case .appWithNoIdentifier(let place): places.contains(PathPattern.comparablePath(of: place))
                case .formula(let name): tools.formulae?.contains(name) ?? true
                case .command(let name, nil): tools.commands?.contains(name) ?? true
                case .command(_, let place?):
                    tools.commandPlaces?.contains(PathPattern.comparablePath(of: place)) ?? true
                }
            }
            .keys.map { $0.lowercased() }
        )
    }

    private func change(_ edit: (inout [String: OrphanOwner]) -> Void) -> ListChange {
        FileLock.whileHeld(beside: url) {
            let stored = url.isMissing ? Entries() : BoundedRead.data(at: url).flatMap(Entries.init)
            guard var entries = stored else { return .notSaved(readProblem()) }
            let before = entries.owners
            edit(&entries.owners)
            for group in Set(before.keys).union(entries.owners.keys) where before[group] != entries.owners[group] {
                entries.unknown[group] = nil
            }
            do {
                try PeelFolder.write(try entries.encoded(), to: url)
                return .saved
            } catch {
                return .notSaved(FileProblem(error))
            }
        }
    }

    private func read() -> [String: OrphanOwner]? {
        BoundedRead.data(at: url).flatMap(Entries.init)?.owners
    }

    /// Why the list there can't be read, or nil when it can, for a caller that holds the lock.
    private func readProblem() -> FileProblem? {
        guard let data = BoundedRead.data(at: url) else { return BoundedRead.whyUnreadable(url) }
        return Entries(data) == nil ? .damaged : nil
    }

    /// The list's entries, each read on its own: one this version doesn't know, such as an owner a newer Peel wrote,
    /// gives its group no owner here and is written back as it was, so a newer Peel finds it again.
    private struct Entries {
        var owners: [String: OrphanOwner] = [:]
        var unknown: [String: Any] = [:]

        init() {}

        /// Nil when the file isn't a list of entries at all.
        init?(_ data: Data) {
            guard let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            for (group, value) in entries {
                let entry = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
                if let owner = entry.flatMap({ try? JSONDecoder().decode(OrphanOwner.self, from: $0) }) {
                    owners[group] = owner
                } else {
                    unknown[group] = value
                }
            }
        }

        func encoded() throws -> Data {
            let known = try JSONSerialization.jsonObject(with: JSONEncoder().encode(owners)) as? [String: Any] ?? [:]
            return try JSONSerialization.data(withJSONObject: unknown.merging(known) { _, owner in owner })
        }
    }
}
