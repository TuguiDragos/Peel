import Foundation
@testable import PeelCore
import Testing

struct LinksInPeelsFolderTests {
    @Test func aFileOfPeelsThatIsALinkIsReadButNeitherWrittenOverNorThrough() throws {
        let directory = try TemporaryDirectory()
        let kept = #"{"org.example.group":"org.example.owner"}"#
        let target = try directory.file("dotfiles/orphan-owners.json", contents: Data(kept.utf8))
        try directory.directory("Peel")
        let link = directory.url.appending(path: "Peel/orphan-owners.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let owners = OrphanOwners(url: link)

        #expect(owners.load() == ["org.example.group": .app("org.example.owner")])
        #expect(owners.give("org.example.other", to: .formula("mole")) == .notSaved(.aLink))
        #expect(link.isSymbolicLink)
        #expect(try String(contentsOf: target, encoding: .utf8) == kept)
    }

    @Test func historyMovesNothingWhileItsJournalIsALinkAndWritesNothingThroughIt() throws {
        let directory = try TemporaryDirectory()
        let history = try directory.file("Peel/removals.json", contents: Data("[]".utf8))
        let target = try directory.file("elsewhere/journal", contents: Data())
        let journal = directory.url.appending(path: "Peel/removals.journal")
        try FileManager.default.createSymbolicLink(at: journal, withDestinationURL: target)
        let item = TrashedItem(
            originalURL: directory.url.appending(path: "home/Library/Caches/org.example.cache"),
            trashedURL: directory.url.appending(path: "home/.Trash/org.example.cache"), date: .now
        )

        #expect(RemovalLog.writeProblem(at: history) == .aLink(journal))
        #expect(!RemovalJournal(beside: history).note([item], batch: UUID(), beforeTheMove: true))
        #expect(try Data(contentsOf: target).isEmpty)
    }
}
