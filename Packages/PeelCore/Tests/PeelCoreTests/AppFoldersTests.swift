import Foundation
@testable import PeelCore
import Testing

struct AppFoldersTests {
    /// A folder chosen for apps is looked through three levels deep. The whole disk, the home folder or a folder
    /// Peel already looks in would only repeat or slow every reading of the apps.
    @Test func refusesAFolderTooBroadOrAlreadyLookedIn() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        for path in ["/", "/Users", "/Volumes", "/System", "/Library", "/Users/someone", "/Users/someone/Library",
                     "/Applications", "/Applications/Utilities", "/Users/someone/Applications"] {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            #expect(AppFolders.refusal(of: folder, home: home) != nil, "\(path)")
        }
        for path in ["/Volumes/Studio/Apps", "/Users/someone/Tools"] {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            #expect(AppFolders.refusal(of: folder, home: home) == nil, "\(path)")
        }
    }

    @Test func remembersTheFoldersChosenForApps() throws {
        let directory = try TemporaryDirectory()
        let folders = AppFolders(url: directory.url.appending(path: "app-folders.json"))
        let studio = directory.url.appending(path: "Studio Apps", directoryHint: .isDirectory)
        #expect(folders.load() == [])

        #expect(folders.add([studio]))
        #expect(folders.load()?.map(\.lastPathComponent) == ["Studio Apps"])
        let chosen = try #require(folders.load())
        #expect(AppCatalog.directories(adding: chosen).count == AppCatalog.standardDirectories.count + 1)

        #expect(folders.remove([studio]))
        #expect(folders.load() == [])
    }

    @Test(.permissionsHold) func aListThatCannotBeReadIsNoEmptyList() throws {
        let directory = try TemporaryDirectory()
        let damaged = try directory.file("damaged.json", contents: Data("not a list".utf8))
        let closed = try directory.file("closed.json", contents: Data("[]".utf8))
        try directory.setPermissions(0o000, of: "closed.json")
        defer { try? directory.setPermissions(0o644, of: "closed.json") }

        #expect(AppFolders(url: damaged).load() == nil)
        #expect(AppFolders(url: closed).load() == nil)
        #expect(AppFolders(url: directory.url.appending(path: "missing.json")).load() == [])
    }

    @Test func startingOverKeepsTheDamagedListBesideAnEmptyOne() throws {
        let directory = try TemporaryDirectory()
        let folders = AppFolders(url: try directory.file("app-folders.json", contents: Data("not a list".utf8)))

        #expect(folders.startOver())

        #expect(folders.load() == [])
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false))
            .filter { $0.hasPrefix("app-folders-damaged-") }
        #expect(kept.count == 1)
    }
}
