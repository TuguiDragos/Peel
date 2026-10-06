import Foundation
@testable import PeelCore
import Testing

struct SelfRemovalTests {
    private func service(
        in directory: borrowing TemporaryDirectory,
        exclusions: Exclusions = .none
    ) throws -> TrashService {
        let trash = try directory.directory("Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(environment: environment, exclusions: exclusions) { url in
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    private func paths(_ urls: [URL]) -> Set<String> {
        Set(urls.map(PathPattern.comparablePath))
    }

    /// History lives in the folder, so it is written first and goes with it.
    @Test func movesTheFolderLastWithTheRecordOfTheRestInside() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let cache = try directory.directory("home/Library/Caches/com.example.peel")
        let folder = try directory.directory("home/Library/Application Support/Peel")

        let result = await SelfRemoval.move(
            [cache, app],
            app: app,
            folder: folder,
            using: try service(in: directory)
        ) { result in
            try? Data("\(result.trashed.count)".utf8).write(to: folder.appending(path: "removals.json"))
        }

        #expect(paths(result.trashed.map(\.originalURL)) == paths([cache, app, folder]))
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        let moved = try #require(
            result.trashed.first {
                PathPattern.comparablePath(of: $0.originalURL) == PathPattern.comparablePath(of: folder)
            }
        )
        #expect(try String(contentsOf: moved.trashedURL.appending(path: "removals.json"), encoding: .utf8) == "2")
    }

    /// When the app stays, its files and its folder stay too: Peel goes on using them.
    @Test func leavesTheFolderWhenTheAppStayed() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let cache = try directory.directory("home/Library/Caches/com.example.peel")
        let folder = try directory.directory("home/Library/Application Support/Peel")

        let result = await SelfRemoval.move(
            [cache, app],
            app: app,
            folder: folder,
            using: try service(in: directory, exclusions: Exclusions(paths: [app]))
        ) { _ in }

        #expect(paths(result.failures.map(\.url)) == paths([app]))
        #expect(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)), "a file moved although Peel stayed")
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func saysNothingOfAFolderThatWasNeverMade() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Peel.app")
        let folder = directory.url.appending(path: "home/Library/Application Support/Peel", directoryHint: .isDirectory)

        let result = await SelfRemoval.move([app], app: app, folder: folder, using: try service(in: directory)) { _ in }

        #expect(result.failures.isEmpty)
        #expect(paths(result.trashed.map(\.originalURL)) == paths([app]))
    }
}
