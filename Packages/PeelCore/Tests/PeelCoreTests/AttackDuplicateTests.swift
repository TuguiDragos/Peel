import Darwin
import Foundation
import Synchronization
@testable import PeelCore
import PeelPrivileged
import Testing
import UniformTypeIdentifiers

/// Attempts to make Duplicates take the last copy of something, move what it did not compare, or offer what the
/// removal guard refuses.
struct AttackDuplicateTests {
    private func bytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    private func scan(_ directory: borrowing TemporaryDirectory, folders: [String]) async throws -> DuplicateScan {
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let options = DuplicateScanOptions(
            folders: folders.map { directory.url.appending(path: $0, directoryHint: .isDirectory) }
        )
        return try await DuplicateFinder(homeDirectory: home).scan(options)
    }

    private func service(
        _ directory: borrowing TemporaryDirectory,
        onTrash: @escaping @Sendable () -> Void = {}
    ) throws -> TrashService {
        let trash = try directory.directory("FakeTrash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(environment: environment) { url in
            onTrash()
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    /// Two hard links to one file look like two copies. If `DuplicateFinder` counted them separately, removing
    /// the "duplicate" would take the only copy.
    @Test func hardLinksAreNotTwoCopies() async throws {
        let directory = try TemporaryDirectory()
        let contents = bytes(4_000)
        let first = try directory.file("home/Documents/report.pdf", contents: contents)
        let second = directory.url.appending(path: "home/Desktop/report.pdf")
        try directory.directory("home/Desktop")
        try FileManager.default.linkItem(at: first, to: second)

        let result = try await scan(directory, folders: ["home"])

        #expect(result.groups.isEmpty, "ATTACK SUCCEEDED: a hard-linked file is offered as its own duplicate")
    }

    /// The same file reached through two scan roots, one of them a symbolic link to the other.
    @Test func oneFileThroughTwoRootsIsNotTwoCopies() async throws {
        let directory = try TemporaryDirectory()
        let real = try directory.directory("home/Archive")
        try directory.file("home/Archive/taxes.pdf", contents: bytes(4_000))
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "home/Shortcut").path(percentEncoded: false),
            withDestinationPath: real.path(percentEncoded: false)
        )

        let result = try await scan(directory, folders: ["home/Archive", "home/Shortcut"])

        #expect(result.groups.isEmpty, "ATTACK SUCCEEDED: one file seen twice is offered as a duplicate group")
    }

    @Test func selectingEveryCopyIsRefused() async throws {
        let directory = try TemporaryDirectory()
        let contents = bytes(4_000)
        try directory.file("home/Documents/a.pdf", contents: contents)
        try directory.file("home/Desktop/b.pdf", contents: contents)
        let found = try await scan(directory, folders: ["home"])
        let group = try #require(found.groups.first)

        let result = await DuplicateRemoval.trash(
            Set(group.files.map(\.url)),
            from: found,
            using: try service(directory)
        )

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.lastCopy, .lastCopy])
        for file in group.files {
            #expect(FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
        }
    }

    /// Something else (a sync client, Finder, another window) can take the kept copy away while the removal runs.
    /// The kept copy is checked again before every move, so the group never loses its last copy.
    @Test func theKeptCopyIsOnlyCheckedBeforeTheFirstMove() async throws {
        let directory = try TemporaryDirectory()
        let contents = bytes(4_000)
        try directory.file("home/Documents/a.pdf", contents: contents)
        try directory.file("home/Documents/b.pdf", contents: contents)
        try directory.file("home/Desktop/c.pdf", contents: contents)
        let found = try await scan(directory, folders: ["home"])
        let group = try #require(found.groups.first)
        let keeper = try #require(group.files.first).url
        let selection = Set(group.files.dropFirst().map(\.url))

        let elsewhere = try directory.directory("Elsewhere")
        let moved = Mutex(false)
        let trashService = try service(directory) {
            moved.withLock { alreadyMoved in
                guard !alreadyMoved else { return }
                alreadyMoved = true
                try? FileManager.default.moveItem(at: keeper, to: elsewhere.appending(path: "taken.pdf"))
            }
        }

        _ = await DuplicateRemoval.trash(selection, from: found, using: trashService)

        let left = group.files.map(\.url).filter {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
        #expect(!left.isEmpty, "ATTACK SUCCEEDED: the group lost every copy")
    }

    /// Duplicates does not scan iCloud Drive: the removal guard refuses everything in it, so every copy offered
    /// there would fail to move.
    @Test func iCloudDuplicatesAreOfferedAndThenRefused() async throws {
        let directory = try TemporaryDirectory()
        let contents = bytes(4_000)
        let cloud = "home/Library/Mobile Documents/com~apple~CloudDocs"
        try directory.file("\(cloud)/a.pdf", contents: contents)
        try directory.file("\(cloud)/a copy.pdf", contents: contents)
        let found = try await scan(directory, folders: [cloud])

        #expect(found.groups.isEmpty, "iCloud Drive is offered for duplicate cleaning")
        guard !found.groups.isEmpty else { return }
        let result = await DuplicateRemoval.trash(found.suggestedSelection, from: found, using: try service(directory))
        #expect(result.failures.map(\.reason) == [.guarded(.protectedLocation)], "and then every removal is refused")
    }

    /// A media library whose app is not installed is a plain folder to the enumerator. A file inside one must not
    /// be offered, because the guard refuses to move it. The library is of a kind no app on this Mac registers as
    /// a package: an installed app's package would be skipped whole, and the test would never reach Peel's rule.
    @Test func neverOffersWhatIsInsideAPhotoLibrary() async throws {
        let kind = try #require(
            ProtectedData.extensions.first { UTType(filenameExtension: $0)?.conforms(to: .package) != true },
            "every library kind is a package on this Mac"
        )
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let contents = Data((0..<4_000).map { _ in UInt8.random(in: 0...255) })
        try directory.file("home/Movies/Old.\(kind)/clip.mov", contents: contents)
        try directory.file("home/Movies/clip.mov", contents: contents)

        let scan = try await DuplicateFinder(homeDirectory: home).scan(DuplicateScanOptions(folders: [home]))

        #expect(scan.groups.isEmpty, "ATTACK SUCCEEDED: a file inside a media library was offered")
        // Two rules stop it, and each is checked: the walk does not go into a library, and the guard refuses what
        // is inside one.
        #expect(DuplicateFinder.isAUserLibrary(directory.url.appending(path: "home/Movies/Old.\(kind)")))
        #expect(
            !RemovalGuard(
                environment: SearchEnvironment(
                    homeDirectory: home,
                    rootDirectory: directory.url.appending(path: "root")
                )
            )
            .allowsRemoval(of: directory.url.appending(path: "home/Movies/Old.\(kind)/clip.mov")))
    }

    /// One folder reached through two scan roots, one of them a link to the other. Offering it as its own
    /// copy would put the only folder in the Trash.
    @Test func oneFolderThroughTwoRootsIsNotTwoCopies() async throws {
        let directory = try TemporaryDirectory()
        let real = try directory.directory("home/Archive")
        try directory.file("home/Archive/taxes.pdf", contents: bytes(4_000))
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "home/Shortcut").path(percentEncoded: false),
            withDestinationPath: real.path(percentEncoded: false)
        )

        let result = try await scan(directory, folders: ["home/Archive", "home/Shortcut"])

        #expect(result.folderGroups.isEmpty, "ATTACK SUCCEEDED: one folder seen twice is offered as a duplicate")
    }

    /// A folder and the folder it sits in, both chosen. The walk reaches the inner one twice, and a folder
    /// offered as a copy of itself would go to the Trash with the only copy in it.
    @Test func aFolderChosenInsideAnotherIsNotItsOwnCopy() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Documents/Archive/taxes.pdf", contents: bytes(4_000))

        let result = try await scan(directory, folders: ["home", "home/Documents"])

        #expect(result.folderGroups.isEmpty, "ATTACK SUCCEEDED: a folder is offered as a copy of itself")
    }

    /// The folders every account starts with can hold identical contents, but the guard refuses to move them, so
    /// they are never offered.
    @Test func neverOffersAFolderTheGuardRefuses() async throws {
        let directory = try TemporaryDirectory()
        let contents = bytes(4_000)
        try directory.file("home/Desktop/report.pdf", contents: contents)
        try directory.file("home/Public/report.pdf", contents: contents)

        let result = try await scan(directory, folders: ["home"])

        #expect(result.folderGroups.isEmpty, "ATTACK SUCCEEDED: a folder the guard refuses was offered")
    }

    /// The copy is written again between the scan and the move, with the same bytes under the same name. It
    /// is another file, and a folder is refused for anything a file would be refused for.
    @Test func aCopyRewrittenWithTheSameBytesIsRefused() async throws {
        let directory = try TemporaryDirectory()
        let contents = bytes(4_000)
        try directory.file("home/Documents/Trip/photo.jpg", contents: contents)
        try directory.file("home/Pictures/Trip/photo.jpg", contents: contents)
        let found = try await scan(directory, folders: ["home"])
        let copy = try #require(found.folderGroups.first?.folders.last?.url)
        try FileManager.default.removeItem(at: copy.appending(path: "photo.jpg"))
        try contents.write(to: copy.appending(path: "photo.jpg"))

        let result = await DuplicateRemoval.trash([], folders: [copy], from: found, using: try service(directory))

        #expect(result.trashed.isEmpty, "ATTACK SUCCEEDED: a folder was moved without being the one compared")
        #expect(result.failures.map(\.reason) == [.changedSinceScan])
    }
}
