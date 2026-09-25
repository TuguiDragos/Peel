import Foundation
import PeelPrivileged
import Testing

/// Put Back works from a record that any process running as the user can rewrite, so the helper keeps its own
/// ledger. These tests try the ways a rewritten record could fool it.
struct HelperLedgerTests {
    private func policy(in directory: borrowing TemporaryDirectory) throws -> PrivilegedPathPolicy {
        try directory.directory("root/Library/Caches")
        try directory.directory("home/.Trash")
        let root = directory.url.path(percentEncoded: false)
        return PrivilegedPathPolicy(
            homeDirectory: root + "home",
            systemLocations: [root + "root/Library/Caches"],
            applicationLocations: [],
            restoreLocations: [root + "root/Library/Caches"]
        )
    }

    private func ledger(in directory: borrowing TemporaryDirectory, maximumEntries: Int = 20_000) throws -> HelperLedger {
        try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist"), maximumEntries: maximumEntries))
    }

    private func path(_ relative: String, in directory: borrowing TemporaryDirectory) -> String {
        directory.url.appending(path: relative).path(percentEncoded: false)
    }

    /// Moves a file the way the helper does: written down first, then renamed into the Trash.
    private func move(_ relative: String, with ledger: HelperLedger, policy: PrivilegedPathPolicy, in directory: borrowing TemporaryDirectory) throws -> String {
        try directory.file(relative)
        let item = try policy.open(path(relative, in: directory)).get()
        #expect(ledger.record([item], movedBy: getuid()))
        return try TrashMover.move(item, into: try #require(policy.openTrash(ownedBy: getuid()))).get()
    }

    @Test func knowsWhereItTookAnItemFromWhateverItIsCalledNow() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        let ledger = try ledger(in: directory)
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        let trashedPath = try move("root/Library/Caches/com.example.plist", with: ledger, policy: policy, in: directory)
        let renamed = path("home/.Trash/renamed in Finder.plist", in: directory)
        try FileManager.default.moveItem(atPath: trashedPath, toPath: renamed)

        let trashed = try #require(policy.openInTrash(renamed, trash: trash))
        let origin = try #require(ledger.origin(of: trashed, movedBy: getuid()))
        #expect(origin.hasSuffix("/root/Library/Caches/com.example.plist"))
        #expect(ledger.origin(of: trashed, movedBy: getuid() + 1) == nil, "another account's request was believed")

        ledger.forget([trashed])
        #expect(ledger.origin(of: trashed, movedBy: getuid()) == nil)
    }

    /// One request can name an item twice, by the same path or by two spellings that reach it. It moves once and
    /// answers for both, and the ledger still knows it afterwards, so Put Back can bring it back.
    @Test func anItemNamedTwiceMovesOnceAndStaysKnown() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        let ledger = try ledger(in: directory)
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        try directory.file("root/Library/Caches/com.example.plist")
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "root/Library/Linked"),
            withDestinationURL: directory.url.appending(path: "root/Library/Caches", directoryHint: .isDirectory)
        )
        let direct = path("root/Library/Caches/com.example.plist", in: directory)
        let linked = path("root/Library/Linked/com.example.plist", in: directory)
        let requests = try [direct, linked, direct].map { (path: $0, item: try policy.open($0).get()) }

        let result = try #require(TrashMover.moveRecorded(requests, into: trash, ledger: ledger, movedBy: getuid()))

        #expect(result.failed.isEmpty, "the same item was reported as failed: \(result.failed)")
        let destination = try #require(result.moved[direct])
        #expect(result.moved[linked] == destination)
        let trashed = try #require(policy.openInTrash(destination, trash: trash))
        #expect(ledger.origin(of: trashed, movedBy: getuid()) != nil, "the ledger forgot the item it moved, so Put Back would refuse it")
    }

    @Test func knowsNothingAboutAnItemItDidNotMove() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        let ledger = try ledger(in: directory)
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        // Dropped into the Trash by hand, which is all a crafted record would need without the ledger.
        try directory.file("home/.Trash/planted.plist")
        let planted = try #require(policy.openInTrash(path("home/.Trash/planted.plist", in: directory), trash: trash))
        #expect(ledger.origin(of: planted, movedBy: getuid()) == nil)

        // The name of something the helper did move, with another file behind it.
        let trashedPath = try move("root/Library/Caches/com.example.plist", with: ledger, policy: policy, in: directory)
        try FileManager.default.removeItem(atPath: trashedPath)
        try Data("swapped".utf8).write(to: URL(filePath: trashedPath))
        let swapped = try #require(policy.openInTrash(trashedPath, trash: trash))
        #expect(ledger.origin(of: swapped, movedBy: getuid()) == nil, "ATTACK SUCCEEDED: a file swapped in under the same name is believed")
    }

    /// The helper serves each connection on a queue of its own, and each request opens the ledger afresh, so two
    /// moves at once must not lose each other's record: an item the ledger forgot can never be put back.
    @Test func movesAtOnceKeepEveryRecord() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        let items = try (0..<200).map { index in
            try directory.file("root/Library/Caches/item \(index).plist")
            return try policy.open(path("root/Library/Caches/item \(index).plist", in: directory)).get()
        }
        let url = directory.url.appending(path: "private/moved.plist")
        DispatchQueue.concurrentPerform(iterations: items.count) { index in
            _ = HelperLedger(at: url)?.record([items[index]], movedBy: getuid())
        }
        let ledger = try ledger(in: directory)
        #expect(items.filter { ledger.origin(of: $0, movedBy: getuid()) == nil }.isEmpty, "a record was lost")
    }

    /// Remove Peel has the helper move its ledger to the Trash before it goes, since nothing else can move it. It
    /// moves only the ledger's own folder, private to the helper, and nothing when there is none.
    @Test func movesItsOwnFolderToTheTrashAndNothingElse() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        let trash = try #require(policy.openTrash(ownedBy: getuid()))
        let folder = path("private", in: directory)

        #expect(try HelperLedger.moveFolder(folder, into: trash).get() == nil, "there was no folder to move")

        let ledger = try ledger(in: directory)
        _ = try move("root/Library/Caches/com.example.plist", with: ledger, policy: policy, in: directory)
        let moved = try #require(try HelperLedger.moveFolder(folder, into: trash).get())
        #expect(moved.hasSuffix("/home/.Trash/private"))
        #expect(FileManager.default.fileExists(atPath: moved + "/moved.plist"))
        #expect(!FileManager.default.fileExists(atPath: folder))

        try directory.directory("shared")
        try directory.setPermissions(0o755, of: "shared")
        #expect(throws: POSIXError.self, "a folder others can read into was moved") {
            try HelperLedger.moveFolder(path("shared", in: directory), into: trash).get()
        }
        try FileManager.default.createSymbolicLink(atPath: folder, withDestinationPath: path("root/Library/Caches", in: directory))
        #expect(throws: POSIXError.self, "a link in the ledger's place was followed") {
            try HelperLedger.moveFolder(folder, into: trash).get()
        }
        #expect(FileManager.default.fileExists(atPath: path("root/Library/Caches", in: directory)))
    }

    @Test func keepsTheNewestEntriesAndOnlyInAFolderOfItsOwn() throws {
        let directory = try TemporaryDirectory()
        let policy = try policy(in: directory)
        let ledger = try ledger(in: directory, maximumEntries: 2)
        let trash = try #require(policy.openTrash(ownedBy: getuid()))

        let paths = try ["a.plist", "b.plist", "c.plist"].map { try move("root/Library/Caches/\($0)", with: ledger, policy: policy, in: directory) }
        let origins = try paths.map { ledger.origin(of: try #require(policy.openInTrash($0, trash: trash)), movedBy: getuid()) }
        #expect(origins.map { $0 != nil } == [false, true, true])

        let attributes = try FileManager.default.attributesOfItem(atPath: path("private/moved.plist", in: directory))
        #expect(attributes[.posixPermissions] as? Int == 0o600)

        try directory.directory("shared")
        try directory.setPermissions(0o755, of: "shared")
        #expect(HelperLedger(at: directory.url.appending(path: "shared/moved.plist")) == nil, "a folder others can read into was accepted")
    }
}
