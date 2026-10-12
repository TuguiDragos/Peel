import Foundation
@testable import PeelCore
import Testing

struct SyncedFoldersTests {
    @Test func knowsWhatEachSyncAppKeepsInStep() throws {
        let directory = try TemporaryDirectory()
        let roots = ["Syncthing": ".stfolder/", "Resilio": ".sync/ID", "Synology": ".SynologyWorkingDirectory/", "MEGA": ".megaignore"]
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
