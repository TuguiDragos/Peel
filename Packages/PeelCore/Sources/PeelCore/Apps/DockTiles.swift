public import Foundation

/// Where the Dock keeps its tiles. Tests stand in for it, so they never change the Dock.
public protocol DockTileStore: Sendable {
    func tiles() -> [Any]?
    func setTiles(_ tiles: [Any]) -> Bool
    func restartTheDock() async
}

/// The Dock's own list of apps, read and written through CFPreferences as the Tweaks are, never in its file:
/// cfprefsd keeps its own copy of the domain. The Dock reads the list again when it starts.
public struct DockPreferences: DockTileStore {
    private static var domain: CFString { "com.apple.dock" as CFString }
    private static var key: CFString { "persistent-apps" as CFString }

    public init() {}

    public func tiles() -> [Any]? {
        CFPreferencesAppSynchronize(Self.domain)
        return CFPreferencesCopyAppValue(Self.key, Self.domain) as? [Any]
    }

    public func setTiles(_ tiles: [Any]) -> Bool {
        guard !CFPreferencesAppValueIsForced(Self.key, Self.domain) else { return false }
        CFPreferencesSetAppValue(Self.key, tiles as CFArray, Self.domain)
        return CFPreferencesAppSynchronize(Self.domain)
    }

    public func restartTheDock() async {
        await TweakRestart.run(.dock)
    }
}

/// An app's tiles in the Dock, which keeps a gone app's tile as a question mark. An uninstall can take them out,
/// and History putting the app back puts them back where they were.
public struct DockTiles: Sendable {
    private struct Removed: Codable {
        let index: Int
        let tile: Data
    }

    private let store: any DockTileStore
    private let memory: URL

    public init(
        store: any DockTileStore = DockPreferences(),
        memory: URL = PeelFolder.url.appending(path: "dock-tiles.json")
    ) {
        self.store = store
        self.memory = memory
    }

    /// Those of `apps` that have a tile in the Dock.
    @concurrent
    public func holding(_ apps: [URL]) async -> Set<URL> {
        let tiles = store.tiles() ?? []
        return Set(apps.filter { !indices(of: $0, in: tiles).isEmpty })
    }

    /// Takes the tiles of `apps` out of the Dock, remembering where each was, and restarts the Dock once. False
    /// when none had a tile, or when that could not be remembered or written.
    public func takeOut(_ apps: [URL]) async -> Bool {
        guard var tiles = store.tiles() else { return false }
        var removed: [String: [Removed]] = [:]
        for app in apps {
            let found = indices(of: app, in: tiles)
            let kept = found.compactMap { index in
                (try? PropertyListSerialization.data(fromPropertyList: tiles[index], format: .binary, options: 0))
                    .map { Removed(index: index, tile: $0) }
            }
            if !found.isEmpty, kept.count == found.count { removed[key(app)] = kept }
        }
        guard !removed.isEmpty, change({ $0.merge(removed) { _, new in new } }) else { return false }
        let taken = Set(removed.values.flatMap { $0.map(\.index) })
        tiles = tiles.indices.filter { !taken.contains($0) }.map { tiles[$0] }
        guard store.setTiles(tiles) else {
            _ = change { entries in removed.keys.forEach { entries[$0] = nil } }
            return false
        }
        await store.restartTheDock()
        return true
    }

    /// Puts back the tiles taken out for the app at `app`, unless the Dock holds one for it again.
    public func putBack(_ app: URL) async {
        guard let removed = FileLock.whileHeld(beside: memory, { read()?[key(app)] }) else { return }
        guard var tiles = store.tiles() else { return }
        if indices(of: app, in: tiles).isEmpty {
            for entry in removed.sorted(by: { $0.index < $1.index }) {
                if let tile = try? PropertyListSerialization.propertyList(from: entry.tile, format: nil) {
                    tiles.insert(tile, at: min(entry.index, tiles.count))
                }
            }
            guard store.setTiles(tiles) else { return }
            await store.restartTheDock()
        }
        _ = change { $0[key(app)] = nil }
    }

    /// The path a tile leads to, from the URL or the path it keeps for its file.
    static func path(of tile: Any) -> String? {
        guard
            let data = (tile as? [String: Any])?["tile-data"] as? [String: Any],
            let file = data["file-data"] as? [String: Any],
            let text = file["_CFURLString"] as? String
        else { return nil }
        let url = (file["_CFURLStringType"] as? Int) == 0 ? URL(filePath: text) : URL(string: text)
        return url.map(PathPattern.comparablePath)
    }

    private func indices(of app: URL, in tiles: [Any]) -> [Int] {
        tiles.indices.filter { Self.path(of: tiles[$0]) == key(app) }
    }

    private func key(_ app: URL) -> String {
        PathPattern.comparablePath(of: app)
    }

    private func change(_ edit: (inout [String: [Removed]]) -> Void) -> Bool {
        FileLock.whileHeld(beside: memory) {
            guard var entries = read() ?? (memory.isMissing ? [:] : nil) else { return false }
            edit(&entries)
            guard let data = try? JSONEncoder().encode(entries) else { return false }
            try? FileManager.default.createDirectory(
                at: memory.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            return (try? data.write(to: memory, options: .atomic)) != nil
        }
    }

    private func read() -> [String: [Removed]]? {
        guard let data = BoundedRead.data(at: memory) else { return nil }
        return try? JSONDecoder().decode([String: [Removed]].self, from: data)
    }
}
