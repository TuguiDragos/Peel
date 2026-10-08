public import Foundation

/// The Dock's two lists of apps: those the person keeps in it, and the recent ones it shows beside them.
public enum DockList: String, Codable, CaseIterable, Sendable {
    case persistent = "persistent-apps"
    case recent = "recent-apps"
}

/// Where the Dock keeps its tiles. Tests stand in for it, so they never change the Dock.
public protocol DockTileStore: Sendable {
    func tiles(in list: DockList) -> [Any]?
    func setTiles(_ tiles: [Any], in list: DockList) -> Bool
    func restartTheDock() async
}

/// The Dock's own lists of apps, read and written through CFPreferences as the Tweaks are, never in its file:
/// cfprefsd keeps its own copy of the domain. The Dock reads the lists again when it starts.
public struct DockPreferences: DockTileStore {
    private static var domain: CFString { "com.apple.dock" as CFString }

    public init() {}

    public func tiles(in list: DockList) -> [Any]? {
        CFPreferencesAppSynchronize(Self.domain)
        return CFPreferencesCopyAppValue(list.rawValue as CFString, Self.domain) as? [Any]
    }

    public func setTiles(_ tiles: [Any], in list: DockList) -> Bool {
        guard !CFPreferencesAppValueIsForced(list.rawValue as CFString, Self.domain) else { return false }
        CFPreferencesSetAppValue(list.rawValue as CFString, tiles as CFArray, Self.domain)
        return CFPreferencesAppSynchronize(Self.domain)
    }

    public func restartTheDock() async {
        await TweakRestart.run(.dock)
    }
}

/// An app's tiles in the Dock, which keeps a gone app's tile as a question mark, and a recent one pointing at the app
/// in the Trash. An uninstall can take them out, and History putting the app back puts them back where they were.
public struct DockTiles: Sendable {
    private struct Removed: Codable {
        let list: DockList
        let index: Int
        let tile: Data

        init(list: DockList, index: Int, tile: Data) {
            self.list = list
            self.index = index
            self.tile = tile
        }

        /// A tile remembered before Peel took out recent ones names no list: it came from the persistent one.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            list = try container.decodeIfPresent(DockList.self, forKey: .list) ?? .persistent
            index = try container.decode(Int.self, forKey: .index)
            tile = try container.decode(Data.self, forKey: .tile)
        }
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
        let lists = DockList.allCases.compactMap { store.tiles(in: $0) }
        return Set(apps.filter { app in lists.contains { !indices(of: app, in: $0).isEmpty } })
    }

    /// Takes the tiles of `apps` out of the Dock, remembering where each was, and restarts the Dock once. False
    /// when none had a tile, or when that could not be remembered or written. Peel removing itself remembers nothing,
    /// since its folder, where the memory is kept, has gone to the Trash.
    public func takeOut(_ apps: [URL], remembering: Bool = true) async -> Bool {
        let lists = Dictionary(uniqueKeysWithValues: DockList.allCases.compactMap { list in
            store.tiles(in: list).map { (list, $0) }
        })
        var removed: [String: [Removed]] = [:]
        for app in apps {
            let found = lists.flatMap { list, tiles in indices(of: app, in: tiles).map { (list, tiles[$0], $0) } }
            let kept = found.compactMap { list, tile, index in
                (try? PropertyListSerialization.data(fromPropertyList: tile, format: .binary, options: 0))
                    .map { Removed(list: list, index: index, tile: $0) }
            }
            if !found.isEmpty, kept.count == found.count { removed[key(app)] = kept }
        }
        guard !removed.isEmpty, !remembering || change({ $0.merge(removed) { _, new in new } }) else { return false }
        var written: Set<DockList> = []
        for (list, tiles) in lists {
            let taken = Set(removed.values.flatMap { $0.filter { $0.list == list }.map(\.index) })
            guard !taken.isEmpty else { continue }
            if store.setTiles(tiles.indices.filter { !taken.contains($0) }.map { tiles[$0] }, in: list) {
                written.insert(list)
            }
        }
        let failed = Set(removed.values.flatMap { $0.map(\.list) }).subtracting(written)
        if remembering, !failed.isEmpty {
            _ = change { entries in
                for key in removed.keys {
                    let left = entries[key]?.filter { !failed.contains($0.list) } ?? []
                    entries[key] = left.isEmpty ? nil : left
                }
            }
        }
        guard !written.isEmpty else { return false }
        await store.restartTheDock()
        return true
    }

    /// Puts back the tiles taken out for the app at `app`, each in its own list, unless that list holds one for it
    /// again.
    public func putBack(_ app: URL) async {
        guard let removed = FileLock.whileHeld(beside: memory, { read()?[key(app)] }) else { return }
        var settled: Set<DockList> = []
        var changed = false
        for list in DockList.allCases {
            let entries = removed.filter { $0.list == list }
            guard !entries.isEmpty, var tiles = store.tiles(in: list) else { continue }
            if indices(of: app, in: tiles).isEmpty {
                for entry in entries.sorted(by: { $0.index < $1.index }) {
                    if let tile = try? PropertyListSerialization.propertyList(from: entry.tile, format: nil) {
                        tiles.insert(tile, at: min(entry.index, tiles.count))
                    }
                }
                guard store.setTiles(tiles, in: list) else { continue }
                changed = true
            }
            settled.insert(list)
        }
        if changed {
            await store.restartTheDock()
        }
        _ = change { entries in
            let left = entries[key(app)]?.filter { !settled.contains($0.list) } ?? []
            entries[key(app)] = left.isEmpty ? nil : left
        }
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
