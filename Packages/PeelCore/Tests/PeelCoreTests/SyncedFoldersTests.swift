import Foundation
@testable import PeelCore
import Testing

struct SyncedFoldersTests {
    @Test(.everySyncAppOnThisMac) func knowsWhatEachSyncAppKeepsInStep() throws {
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

    @Test(.everySyncAppOnThisMac) func namesTheAppThatKeepsAFolderInStepAndItsMarker() throws {
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

    @Test func aMarkerCountsOnlyWhileItsAppIsOnThisMac() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/.stfolder")
        try directory.file("home/Music/.megaignore")
        let notes = try directory.file("home/Documents/notes.txt")
        let set = try directory.file("home/Music/Live/set.txt")
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)

        SyncApp.$standIn.withValue({ $0 == .mega }) {
            let synced = SyncedFolders()
            #expect(synced.keeper(of: notes) == nil)
            #expect(synced.keeper(of: set) == .app(.mega, marker: home.appending(path: "Music/.megaignore")))
            #expect(!synced.marksAFolder([home.appending(path: ".stfolder"), notes]))
            #expect(synced.marksAFolder([home.appending(path: "Music/.megaignore"), set]))
        }
    }

    @Test(arguments: [".stfolder/", ".stfolder", ".STFOLDER/", ".sync/ID", ".SynologyWorkingDirectory/", ".megaignore",
                      ".dropbox.cache/"])
    func aMarkerOfAnyKindCountsOnlyWhileItsAppIsOnThisMac(marker: String) throws {
        let directory = try TemporaryDirectory()
        if marker.hasSuffix("/") {
            try directory.directory("Sync/" + marker)
        } else {
            try directory.file("Sync/" + marker)
        }
        let notes = try directory.file("Sync/Documents/notes.txt")

        let present = SyncApp.$standIn.withValue({ _ in true }) { SyncedFolders().keeper(of: notes) }
        let gone = SyncApp.$standIn.withValue({ _ in false }) { SyncedFolders().keeper(of: notes) }

        #expect(present != nil)
        #expect(gone == nil)
    }

    @Test func aDeadLinkNamedLikeAMarkerCountsOnlyWhileItsAppIsOnThisMac() throws {
        let directory = try TemporaryDirectory()
        let notes = try directory.file("Sync/Documents/notes.txt")
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "Sync/.stfolder").path(percentEncoded: false),
            withDestinationPath: "/Volumes/org-example-not-connected/Sync"
        )

        #expect(SyncApp.$standIn.withValue({ _ in true }) { SyncedFolders().keeper(of: notes) } != nil)
        #expect(SyncApp.$standIn.withValue({ _ in false }) { SyncedFolders().keeper(of: notes) } == nil)
    }

    @Test func findsASyncAppWhereTheMacKeepsIt() throws {
        let directory = try TemporaryDirectory()
        let name = "org-example-sync-\(UUID().uuidString)"
        let folder = PathPattern.comparablePath(of: try directory.directory("bin"))

        #expect(SyncApp.isOnThisMac(bundleIdentifiers: ["com.apple.TextEdit"], program: nil))
        #expect(!SyncApp.isOnThisMac(bundleIdentifiers: ["org.example.sync"], program: nil))
        #expect(!SyncApp.isOnThisMac(bundleIdentifiers: [], program: name, programFolders: [folder]))
        let program = try directory.file("bin/\(name)")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: program.path(percentEncoded: false)
        )
        #expect(SyncApp.isOnThisMac(bundleIdentifiers: [], program: name, programFolders: [folder]))
    }

    @Test func findsASyncAppByTheProgramThatRuns() throws {
        let directory = try TemporaryDirectory()
        let name = "org-example-sync-\(UUID().uuidString.prefix(8))"
        let process = try directory.runningProgram("Elsewhere/\(name)")
        defer { process.terminate() }

        #expect(SyncApp.isOnThisMac(bundleIdentifiers: [], program: name, programFolders: []))
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

    @Test(.everySyncAppOnThisMac) func readsAFolderAsSyncedFromItsListingAlone() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Resilio/.sync/ID")
        try directory.file("Tool/.sync/settings.json")
        func listing(_ folder: String) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(
                at: directory.url.appending(path: folder, directoryHint: .isDirectory), includingPropertiesForKeys: nil
            )
        }

        let synced = SyncedFolders()
        #expect(synced.marksAFolder(try listing("Resilio")))
        #expect(!synced.marksAFolder(try listing("Tool")))
        #expect(synced.marksAFolder([URL(filePath: "/Sync/.stfolder"), URL(filePath: "/Sync/notes.txt")]))
        #expect(!synced.marksAFolder([URL(filePath: "/Sync/notes.txt")]))
    }
}

/// Says for the test it marks whether every sync app is on this Mac, since no test can install or remove one.
struct SyncAppsOnThisMac: TestTrait, TestScoping {
    let areThere: Bool

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        let areThere = areThere
        try await SyncApp.$standIn.withValue({ _ in areThere }) { try await function() }
    }
}

extension Trait where Self == SyncAppsOnThisMac {
    static var everySyncAppOnThisMac: Self { Self(areThere: true) }
    static var noSyncAppOnThisMac: Self { Self(areThere: false) }
}

extension SyncKeeper {
    /// The keeper with its marker's links resolved, since a folder's listing names `/var` as `/private/var`.
    var resolved: SyncKeeper {
        guard case .app(let app, let marker) = self else { return self }
        return .app(app, marker: URL(filePath: PathPattern.comparablePath(of: marker.resolvingSymlinksInPath())))
    }
}
