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

    /// Sets a list that cannot be read aside, under another name, so the person can say again what belongs to what.
    @discardableResult
    public func startOver() -> StartOver {
        FileLock.whileHeld(beside: url) {
            guard !url.isMissing, read() == nil else { return .notNeeded }
            return DamagedFile.setAside(url) == nil ? .couldNotSetAside : .started
        }
    }

    /// Records that `group` belongs to the app `bundleIdentifier`. False when the choice could not be saved, or when
    /// the file is there and cannot be read, since writing over it would lose the choices it holds.
    @discardableResult
    public func give(_ group: String, to bundleIdentifier: String) -> Bool {
        change { $0[group.lowercased()] = bundleIdentifier }
    }

    /// Forgets which app each of `groups` belongs to, so they are listed again.
    @discardableResult
    public func take(_ groups: [String]) -> Bool {
        change { owners in groups.forEach { owners[$0.lowercased()] = nil } }
    }

    private func change(_ edit: (inout [String: String]) -> Void) -> Bool {
        FileLock.whileHeld(beside: url) {
            guard var owners = read() ?? (url.isMissing ? [:] : nil) else { return false }
            edit(&owners)
            guard let data = try? JSONEncoder().encode(owners) else { return false }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return (try? data.write(to: url, options: .atomic)) != nil
        }
    }

    private func read() -> [String: String]? {
        guard let data = BoundedRead.data(at: url) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}
