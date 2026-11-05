public import Foundation
internal import PeelPrivileged

/// What a group of orphaned files belongs to, as the person said: an app, by its bundle identifier, or a command-line
/// tool Homebrew installed, by the name of its formula.
public enum OrphanOwner: Sendable, Hashable {
    case app(String)
    case formula(String)
}

extension OrphanOwner: Codable {
    private enum CodingKeys: String, CodingKey {
        case formula
    }

    /// An app is written as its bundle identifier alone, as every list written before tools could be named, and a
    /// formula under its own key.
    public init(from decoder: any Decoder) throws {
        if let identifier = try? decoder.singleValueContainer().decode(String.self) {
            self = .app(identifier)
        } else {
            self = .formula(try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .formula))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .app(let identifier):
            var container = encoder.singleValueContainer()
            try container.encode(identifier)
        case .formula(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .formula)
        }
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

    /// The groups, lowercased, whose owner is on this Mac: an app among `apps`, the installed bundle identifiers, or a
    /// formula among `formulae`, the installed ones. While the formulae aren't known, every group given to one stays
    /// out, since the person's word stands until Peel knows better.
    public static func given(
        _ owners: [String: OrphanOwner], apps: Set<String>, formulae: Set<String>?
    ) -> Set<String> {
        Set(
            owners.filter { _, owner in
                switch owner {
                case .app(let identifier): apps.contains(identifier.lowercased())
                case .formula(let name): formulae?.contains(name) ?? true
                }
            }
            .keys.map { $0.lowercased() }
        )
    }

    private func change(_ edit: (inout [String: OrphanOwner]) -> Void) -> ListChange {
        FileLock.whileHeld(beside: url) {
            guard var owners = read() ?? (url.isMissing ? [:] : nil) else { return .notSaved(readProblem()) }
            edit(&owners)
            do {
                try PeelFolder.write(try JSONEncoder().encode(owners), to: url)
                return .saved
            } catch {
                return .notSaved(.failed(SystemError(error)))
            }
        }
    }

    private func read() -> [String: OrphanOwner]? {
        BoundedRead.data(at: url).flatMap(decoded)
    }

    /// Why the list there can't be read, or nil when it can, for a caller that holds the lock.
    private func readProblem() -> FileProblem? {
        guard let data = BoundedRead.data(at: url) else { return BoundedRead.whyUnreadable(url) }
        return decoded(data) == nil ? .damaged : nil
    }

    private func decoded(_ data: Data) -> [String: OrphanOwner]? {
        try? JSONDecoder().decode([String: OrphanOwner].self, from: data)
    }
}
