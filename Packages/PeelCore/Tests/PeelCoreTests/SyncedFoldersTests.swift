import Foundation
@testable import PeelCore
import Testing

struct SyncedFoldersTests {
    @Test func knowsWhatEachSyncAppKeepsInStep() throws {
        let directory = try TemporaryDirectory()
        let roots = [
            "Syncthing": ".stfolder/", "Resilio": ".sync/ID", "Synology": ".SynologyWorkingDirectory/", "MEGA": ".megaignore",
            "Dropbox": ".dropbox.cache/",
        ]
        for (root, marker) in roots {
            if marker.hasSuffix("/") {
                try directory.directory("home/\(root)/\(marker)")
            } else {
                try directory.file("home/\(root)/\(marker)")
            }
            try directory.file("home/\(root)/Projects/notes.txt")
        }
        try directory.file("home/Plain/Projects/notes.txt")
        let synced = SyncedFolders()

        for root in roots.keys {
            let folder = directory.url.appending(path: "home/\(root)", directoryHint: .isDirectory)
            #expect(synced.syncsToOtherDevices(folder), "\(root)")
            #expect(synced.syncsToOtherDevices(folder.appending(path: "Projects", directoryHint: .isDirectory)), "\(root)")
            #expect(synced.syncsToOtherDevices(folder.appending(path: "Projects/notes.txt")), "\(root)")
        }
        #expect(!synced.syncsToOtherDevices(directory.url.appending(path: "home/Plain/Projects/notes.txt")))
    }

    @Test func namesTheAppThatKeepsAFolderInStepAndItsMarker() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.stfolder")
        try directory.file("home/Documents/notes.txt")
        try directory.file("home/Music/.megaignore")
        try directory.file("home/Music/Live/set.txt")
        try directory.file("home/Sync/.sync/ID")
        try directory.file("home/Sync/notes.txt")
        let synced = SyncedFolders()
        func keeper(_ path: String) -> (SyncApp, String)? {
            guard case .app(let app, let marker) = synced.keeper(of: directory.url.appending(path: path)) else {
                return nil
            }
            return (app, marker.path(percentEncoded: false))
        }
        let home = directory.url.appending(path: "home").path(percentEncoded: false)

        #expect(keeper("home/Documents/notes.txt")! == (.syncthing, home + "/.stfolder"))
        #expect(keeper("home/Music/Live/set.txt")! == (.mega, home + "/Music/.megaignore"))
        #expect(keeper("home/Sync/notes.txt")! == (.resilioSync, home + "/Sync/.sync/ID"))
        #expect(synced.keeper(of: directory.url.appending(path: "notes.txt")) == nil)
    }

    @Test func aRefusalLogReadsBackTheAppAndItsMarker() {
        let keeper = SyncKeeper.app(.dropbox, marker: URL(filePath: "/Users/me/Dropbox/.dropbox.cache"))

        #expect(SyncKeeper(detail: keeper.detail) == keeper)
        #expect(SyncKeeper.cloud.detail == nil)
        #expect(SyncKeeper(detail: nil) == .cloud)
        #expect(SyncKeeper(detail: "rsync\n/Users/me/.stfolder") == .cloud)
    }

    @Test func aSyncFolderWithoutResiliosIdentifierMarksNothing() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Tool/.sync/settings.json")
        let notes = try directory.file("Tool/notes.txt")

        #expect(!SyncedFolders().syncsToOtherDevices(notes))
    }

    @Test func readsAFolderAsSyncedFromItsListingAlone() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Resilio/.sync/ID")
        try directory.file("Tool/.sync/settings.json")
        func listing(_ folder: String) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(
                at: directory.url.appending(path: folder, directoryHint: .isDirectory), includingPropertiesForKeys: nil
            )
        }

        #expect(SyncedFolders.marksAFolder(try listing("Resilio")))
        #expect(!SyncedFolders.marksAFolder(try listing("Tool")))
        #expect(SyncedFolders.marksAFolder([URL(filePath: "/Sync/.stfolder"), URL(filePath: "/Sync/notes.txt")]))
        #expect(!SyncedFolders.marksAFolder([URL(filePath: "/Sync/notes.txt")]))
    }
}

extension SyncKeeper {
    /// The keeper with its marker's links resolved, since a folder's listing names `/var` as `/private/var`.
    var resolved: SyncKeeper {
        guard case .app(let app, let marker) = self else { return self }
        return .app(app, marker: URL(filePath: PathPattern.comparablePath(of: marker.resolvingSymlinksInPath())))
    }
}
