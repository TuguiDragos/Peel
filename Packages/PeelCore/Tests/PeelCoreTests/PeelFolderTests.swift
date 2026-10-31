import Foundation
@testable import PeelCore
import Testing

struct PeelFolderTests {
    /// Remove Peel moves this one folder, so everything Peel writes has to live in it.
    @Test func everythingPeelWritesLivesInItsFolder() {
        let folder = PathPattern.comparablePath(of: PeelFolder.url)
        let written = [
            TeamRegistry.defaultURL, ExclusionStore.defaultURL, AppMemory.defaultURL,
            RemovalHistory.defaultURL, RemovalHistory.refusalsURL,
            RemovalJournal(beside: RemovalHistory.defaultURL).url,
            PreferenceBackup.defaultDirectory, DigestMemory.defaultURL,
        ]
        for url in written {
            #expect(PathPattern.comparablePath(of: url.deletingLastPathComponent()) == folder, "\(url.path(percentEncoded: false))")
        }
    }

    @Test func nothingIsWrittenInAFolderRemovePeelTook() async throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url.appending(path: "Peel", directoryHint: .isDirectory)
        let file = { (name: String) in folder.appending(path: name) }
        PeelFolder.take(folder)

        FileLock.whileHeld(beside: file("a.json")) {}
        #expect(!AppFolders(url: file("app-folders.json")).add([directory.url]))
        #expect(!HomebrewChoice(url: file("homebrew.json")).save(nil))
        #expect(!ShellFile.write(ShellFile.Choices(), to: file("Terminal/zshrc")))
        #expect(!SSHFile.write([], to: file("Terminal/ssh_config")))
        await ReleaseNotesStore(url: file("release-notes.json")).save(ReleaseNotesMemory())
        let known = KnownDigests(entries: [:], day: 0)
        let identity = try #require(FileIdentity.of(try directory.file("a file")))
        known.keep(sample: try #require(ContentDigest(bytes: [UInt8](repeating: 1, count: 32))), of: identity)
        DigestMemory(url: file("digests.bin")).save(known)
        _ = await RefusalLog(url: file("refusals.json")).add(
            [TrashFailure(url: directory.url, reason: .failed("no"))], source: "A test", tool: "test"
        )
        if case .saved = await ExclusionStore(url: file("exclusions.json")).change({ $0 = Exclusions() }) {
            Issue.record("the list was saved in a folder that went")
        }

        #expect(folder.isMissing)
    }

    @Test func aFileWrittenInAFolderThatStaysAfterItWasTakenDoesNotLandThere() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Peel")
        PeelFolder.take(folder)

        #expect(!HomebrewChoice(url: folder.appending(path: "homebrew.json")).save(nil))
        FileLock.whileHeld(beside: folder.appending(path: "a.json")) {}

        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty)
    }

    @Test func aFolderBesideOneTakenStaysOpen() throws {
        let directory = try TemporaryDirectory()
        PeelFolder.take(directory.url.appending(path: "Peel", directoryHint: .isDirectory))

        #expect(HomebrewChoice(url: directory.url.appending(path: "Peel 2/homebrew.json")).save(nil))
    }

    @Test func onlyThisFolderWritesAFileOfPeelsWhole() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/PeelCore")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let writers = try files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.filter {
            try String(contentsOf: $0, encoding: .utf8).contains("options: .atomic")
        }
        #expect(writers.map(\.lastPathComponent) == ["PeelFolder.swift"])
    }

    @Test func aReadLeavesAHomeAsItFoundIt() async throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url.appending(path: "Peel", directoryHint: .isDirectory)
        let file = { (name: String) in folder.appending(path: name) }

        _ = AppFolders(url: file("app-folders.json")).load()
        _ = DigestMemory(url: file("digests.bin")).load()
        _ = await RemovalLog(url: file("removals.json")).load()
        _ = await RemovalLog(url: file("removals.json")).placesInTheTrash()
        _ = await RefusalLog(url: file("refusals.json")).load()
        _ = await RefusalLog(url: file("refusals.json")).holdsNothing()
        await DockTiles(store: EmptyDock(), memory: file("dock-tiles.json")).putBack([directory.url])
        _ = await ExclusionStore(url: file("exclusions.json")).load()
        _ = await AppMemory(url: file("apps.json")).load()
        _ = OrphanOwners(url: file("orphan-owners.json")).load()
        _ = await LeftForAnAdministrator(url: file("left.json")).load()

        #expect(folder.isMissing)
    }
}

private struct EmptyDock: DockTileStore {
    func tiles(in list: DockList) -> [Any]? { [] }
    func setTiles(_ tiles: [Any], in list: DockList) -> Bool { true }
    func restartTheDock() async {}
}
