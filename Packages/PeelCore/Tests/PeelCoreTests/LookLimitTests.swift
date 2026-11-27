import Darwin
import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

struct LookLimitTests {
    @Test func aLookReadsNoFolderWithMoreEntriesThanItsLimit() throws {
        let directory = try TemporaryDirectory()
        for name in 0..<6 { try directory.file("folder/\(name)") }
        let folder = directory.url.appending(path: "folder").path(percentEncoded: false)

        #expect(FolderEntries.count(at: folder) == 6)
        #expect(ProtectedData.look(in: folder, followingLinks: false, limit: 5) == .failure(.tooMany))
        #expect((try? ProtectedData.look(in: folder, followingLinks: false, limit: 6).get())?.count == 6)
    }

    @Test func countsAFolderOnADiskThatDoesNotTellHowManyEntriesItHolds() async throws {
        let directory = try TemporaryDirectory()
        let disk = try await ScratchVolume(fileSystem: "ExFAT", mountedAt: directory.url.appending(path: "disk"))
        let folder = disk.url.appending(path: "folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in 0..<6 {
            FileManager.default.createFile(atPath: folder.appending(path: "\(name)").path(percentEncoded: false), contents: nil)
        }
        let path = folder.path(percentEncoded: false)

        #expect(FolderEntries.count(at: path) == nil)
        #expect(ProtectedData.look(in: path, followingLinks: false, limit: 5) == .failure(.tooMany))
        let names = try? ProtectedData.look(in: path, followingLinks: false, limit: 6).get()
        #expect(names?.sorted() == (0..<6).map(String.init))
    }

    @Test func aFolderTooFullToLookThroughIsKnownNotToBeEmpty() {
        var finding = ProtectedData.Finding.nothing
        finding.note(.notKnown)
        #expect(finding == .notKnown)
        finding.note(.tooMany)
        finding.note(.notKnown)
        #expect(finding == .tooMany)
    }

    @Test func whatHoldsAFolderTooFullToLookThroughStaysWithoutItBeingRead() async throws {
        let directory = try TemporaryDirectory()
        let big = try directory.directory("home/Library/Caches/net.example.client/big")
        let path = big.path(percentEncoded: false)
        for number in 0...FolderEntries.lookLimit {
            let descriptor = open(path + "/\(number)", O_CREAT | O_WRONLY | O_EXCL, 0o644)
            if descriptor >= 0 { close(descriptor) }
        }
        let folder = big.deletingLastPathComponent()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory),
            userCacheDirectory: directory.url.appending(path: "var/C", directoryHint: .isDirectory),
            userTemporaryDirectory: directory.url.appending(path: "var/T", directoryHint: .isDirectory)
        )
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Tunewell.app"), bundleIdentifier: "net.example.client", name: "Tunewell"
        )

        let place = folder.path(percentEncoded: false)
        #expect(ProtectedData.holdsABrowserWallet(place) == .tooMany)
        #expect(ProtectedData.holdsALibrary(place) == .tooMany)
        #expect(ProtectedData.holdsWorkKeptInACache(place) == .tooMany)
        #expect(Exclusions(bundleIdentifiers: ["org.example.excluded"]).holdsSomething(folder) == .tooMany)
        #expect(RemovalGuard(environment: environment).refusal(of: folder) == .tooManyToLookThrough)

        let scan = await LeftoverScanner(environment: environment).scan(app, installedApps: [app])
        let found = try #require(scan.leftovers.first { $0.url.lastPathComponent == "net.example.client" })
        #expect(found.match.heldBack == .tooManyToLookThrough)
        #expect(found.match.heldBack?.cannotBeMoved == false)

        let orphans = await OrphanScanner(environment: environment) { _ in false }.scan(installedApps: [])
        let orphan = try #require(orphans.groups.flatMap(\.items).first { $0.url.lastPathComponent == "net.example.client" })
        #expect(orphan.heldBack == .tooManyToLookThrough)
    }
}
