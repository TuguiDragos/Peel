import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct DockTilesTests {
    /// Keeps each list as a property list, as cfprefsd does.
    private final class Store: DockTileStore {
        let saved = Mutex<[DockList: Data]>([:])
        let refusing = Mutex<Set<DockList>>([])
        let restarts = Atomic(0)

        init(_ tiles: [Any], recent: [Any]? = nil) {
            _ = setTiles(tiles, in: .persistent)
            if let recent {
                _ = setTiles(recent, in: .recent)
            }
        }

        func tiles(in list: DockList) -> [Any]? {
            guard let data = saved.withLock({ $0[list] }) else { return nil }
            return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any]
        }

        func setTiles(_ tiles: [Any], in list: DockList) -> Bool {
            guard !refusing.withLock({ $0.contains(list) }),
                  let data = try? PropertyListSerialization.data(fromPropertyList: tiles, format: .binary, options: 0)
            else { return false }
            saved.withLock { $0[list] = data }
            return true
        }

        func restartTheDock() async {
            restarts.add(1, ordering: .relaxed)
        }

        func paths(in list: DockList = .persistent) -> [String] {
            (tiles(in: list) ?? []).compactMap { DockTiles.path(of: $0) }
        }
    }

    private static func tile(_ url: String, type: Int = 15) -> [String: Any] {
        ["tile-data": ["file-data": ["_CFURLString": url, "_CFURLStringType": type]], "tile-type": "file-tile"]
    }

    private let studio = URL(filePath: "/Applications/org.example.Studio.app", directoryHint: .isDirectory)

    /// The Dock keeps a gone app's tile as a question mark. Peel takes out only the tiles of that copy, and History
    /// putting the app back puts its tile back where it was.
    @Test func takesOutTheAppsTileAndPutsItBackWhereItWas() async throws {
        let directory = try TemporaryDirectory()
        let store = Store([
            Self.tile("file:///System/Applications/Mail.app/"),
            Self.tile("file:///Applications/org.example.Studio.app/"),
            Self.tile("/Volumes/Other/org.example.Studio.app", type: 0),
            Self.tile("file:///Applications/org.example.Notes.app/"),
        ])
        let tiles = DockTiles(store: store, memory: directory.url.appending(path: "dock-tiles.json"))

        #expect(await tiles.holding([studio]) == [studio])
        #expect(await tiles.takeOut([studio]))
        #expect(store.paths() == [
            "/System/Applications/Mail.app", "/Volumes/Other/org.example.Studio.app",
            "/Applications/org.example.Notes.app",
        ])
        #expect(await tiles.holding([studio]).isEmpty)

        await tiles.putBack(studio)
        #expect(store.paths() == [
            "/System/Applications/Mail.app", "/Applications/org.example.Studio.app",
            "/Volumes/Other/org.example.Studio.app", "/Applications/org.example.Notes.app",
        ])
        #expect(store.restarts.load(ordering: .relaxed) == 2)

        await tiles.putBack(studio)
        #expect(store.paths().count == 4, "a tile was put back twice")
    }

    @Test func takesOutATileWithoutRememberingItInAFolderThatIsGone() async throws {
        let directory = try TemporaryDirectory()
        let store = Store([Self.tile("file:///Applications/org.example.Studio.app/")])
        let folder = directory.url.appending(path: "Peel", directoryHint: .isDirectory)
        let tiles = DockTiles(store: store, memory: folder.appending(path: "dock-tiles.json"))

        #expect(await tiles.takeOut([studio], remembering: false))
        #expect(store.paths().isEmpty)
        #expect(store.restarts.load(ordering: .relaxed) == 1)
        #expect(folder.isMissing)
    }

    /// Several apps removed together restart the Dock once, and each comes back to its own place.
    @Test func takesOutSeveralAppsTilesWithOneRestart() async throws {
        let directory = try TemporaryDirectory()
        let tools = URL(filePath: "/Applications/org.example.Tools.app", directoryHint: .isDirectory)
        let store = Store([
            Self.tile("file:///System/Applications/Mail.app/"),
            Self.tile("file:///Applications/org.example.Studio.app/"),
            Self.tile("file:///Applications/org.example.Notes.app/"),
            Self.tile("file:///Applications/org.example.Tools.app/"),
        ])
        let tiles = DockTiles(store: store, memory: directory.url.appending(path: "dock-tiles.json"))

        #expect(await tiles.takeOut([studio, tools]))
        #expect(store.paths() == ["/System/Applications/Mail.app", "/Applications/org.example.Notes.app"])
        #expect(store.restarts.load(ordering: .relaxed) == 1)

        await tiles.putBack(studio)
        await tiles.putBack(tools)
        #expect(store.paths() == [
            "/System/Applications/Mail.app", "/Applications/org.example.Studio.app",
            "/Applications/org.example.Notes.app", "/Applications/org.example.Tools.app",
        ])
    }

    @Test func leavesTheDockAsItIsForAnAppWithNoTile() async throws {
        let directory = try TemporaryDirectory()
        let store = Store([Self.tile("file:///Applications/org.example.Notes.app/")])
        let tiles = DockTiles(store: store, memory: directory.url.appending(path: "dock-tiles.json"))

        #expect(!(await tiles.takeOut([studio])))
        await tiles.putBack(studio)
        #expect(store.paths() == ["/Applications/org.example.Notes.app"])
        #expect(store.restarts.load(ordering: .relaxed) == 0)
    }

    /// A tile the person added again meanwhile is not doubled when History puts the app back.
    @Test func neverDoublesATileThePersonAddedAgain() async throws {
        let directory = try TemporaryDirectory()
        let store = Store([Self.tile("file:///Applications/org.example.Studio.app/")])
        let tiles = DockTiles(store: store, memory: directory.url.appending(path: "dock-tiles.json"))

        #expect(await tiles.takeOut([studio]))
        _ = store.setTiles([Self.tile("file:///Applications/org.example.Studio.app/")], in: .persistent)
        await tiles.putBack(studio)

        #expect(store.paths() == ["/Applications/org.example.Studio.app"])
    }

    @Test func takesOutTheAppsRecentTileAndPutsItBackThere() async throws {
        let directory = try TemporaryDirectory()
        let store = Store(
            [Self.tile("file:///System/Applications/Mail.app/")],
            recent: [
                Self.tile("file:///Applications/org.example.Notes.app/"),
                Self.tile("file:///Applications/org.example.Studio.app/"),
            ]
        )
        let tiles = DockTiles(store: store, memory: directory.url.appending(path: "dock-tiles.json"))

        #expect(await tiles.holding([studio]) == [studio])
        #expect(await tiles.takeOut([studio]))
        #expect(store.paths(in: .recent) == ["/Applications/org.example.Notes.app"])
        #expect(store.paths() == ["/System/Applications/Mail.app"])

        await tiles.putBack(studio)
        #expect(store.paths(in: .recent) == [
            "/Applications/org.example.Notes.app", "/Applications/org.example.Studio.app",
        ])
        #expect(store.paths() == ["/System/Applications/Mail.app"])
    }

    @Test func takesOutTheAppsTilesFromBothListsWithOneRestart() async throws {
        let directory = try TemporaryDirectory()
        let store = Store(
            [Self.tile("file:///Applications/org.example.Studio.app/")],
            recent: [Self.tile("file:///Applications/org.example.Studio.app/")]
        )
        let tiles = DockTiles(store: store, memory: directory.url.appending(path: "dock-tiles.json"))

        #expect(await tiles.takeOut([studio]))
        #expect(store.paths().isEmpty)
        #expect(store.paths(in: .recent).isEmpty)
        #expect(store.restarts.load(ordering: .relaxed) == 1)

        await tiles.putBack(studio)
        #expect(store.paths() == ["/Applications/org.example.Studio.app"])
        #expect(store.paths(in: .recent) == ["/Applications/org.example.Studio.app"])
        #expect(store.restarts.load(ordering: .relaxed) == 2)
    }

    @Test func putsBackATileRememberedWithoutItsList() async throws {
        let directory = try TemporaryDirectory()
        let memory = directory.url.appending(path: "dock-tiles.json")
        let tile = try PropertyListSerialization.data(
            fromPropertyList: Self.tile("file:///Applications/org.example.Studio.app/"), format: .binary, options: 0
        )
        let entry: [String: Any] = ["index": 0, "tile": tile.base64EncodedString()]
        try JSONSerialization.data(withJSONObject: [PathPattern.comparablePath(of: studio): [entry]]).write(to: memory)
        let store = Store([Self.tile("file:///System/Applications/Mail.app/")], recent: [])

        await DockTiles(store: store, memory: memory).putBack(studio)

        #expect(store.paths() == ["/Applications/org.example.Studio.app", "/System/Applications/Mail.app"])
        #expect(store.paths(in: .recent).isEmpty)
    }

    @Test func remembersOnlyTheTilesThatLeftTheDock() async throws {
        let directory = try TemporaryDirectory()
        let store = Store(
            [Self.tile("file:///Applications/org.example.Studio.app/")],
            recent: [Self.tile("file:///Applications/org.example.Studio.app/")]
        )
        store.refusing.withLock { $0 = [.recent] }
        let tiles = DockTiles(store: store, memory: directory.url.appending(path: "dock-tiles.json"))

        #expect(await tiles.takeOut([studio]))
        #expect(store.paths().isEmpty)
        #expect(store.paths(in: .recent) == ["/Applications/org.example.Studio.app"])

        store.refusing.withLock { $0 = [] }
        _ = store.setTiles([], in: .recent)
        await tiles.putBack(studio)

        #expect(store.paths() == ["/Applications/org.example.Studio.app"])
        #expect(store.paths(in: .recent).isEmpty, "a tile that never left the Dock was put back")
    }
}
