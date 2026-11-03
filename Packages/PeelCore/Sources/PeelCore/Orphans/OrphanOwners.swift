public import Foundation
internal import PeelPrivileged

/// The orphaned files the person said belong to an installed app, by the identifier of their group, so Orphaned
/// Files stops listing them while that app is installed. It only ever takes rows out of the list: nothing is moved.
public struct OrphanOwners: Sendable {
    public let url: URL

    public init(url: URL = OrphanOwners.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        PeelFolder.url.appending(path: "orphan-owners.json")
    }

    /// Each group's identifier, lowercased, and the bundle identifier of the app it belongs to: none while the file
    /// isn't there, and nil when it is there and can't be read, which lists those groups again.
    public func load() -> [String: String]? {
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

    /// Records that `group` belongs to the app `bundleIdentifier`.
    @discardableResult
    public func give(_ group: String, to bundleIdentifier: String) -> ListChange {
        change { $0[group.lowercased()] = bundleIdentifier }
    }

    /// Forgets which app each of `groups` belongs to, so they are listed again.
    @discardableResult
    public func take(_ groups: [String]) -> ListChange {
        change { owners in groups.forEach { owners[$0.lowercased()] = nil } }
    }

    private func change(_ edit: (inout [String: String]) -> Void) -> ListChange {
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

    private func read() -> [String: String]? {
        BoundedRead.data(at: url).flatMap(decoded)
    }

    /// Why the list there can't be read, or nil when it can, for a caller that holds the lock.
    private func readProblem() -> FileProblem? {
        guard let data = BoundedRead.data(at: url) else { return BoundedRead.whyUnreadable(url) }
        return decoded(data) == nil ? .damaged : nil
    }

    private func decoded(_ data: Data) -> [String: String]? {
        try? JSONDecoder().decode([String: String].self, from: data)
    }
}
