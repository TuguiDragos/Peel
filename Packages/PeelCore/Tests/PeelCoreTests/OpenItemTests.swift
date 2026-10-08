import Darwin
import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

struct OpenItemTests {
    private func item(_ url: URL) throws -> OpenItem {
        try OpenItem.at(url.path(percentEncoded: false)).get()
    }

    private func move(_ item: URL, to destination: URL) -> Bool {
        rename(item.path(percentEncoded: false), destination.path(percentEncoded: false)) == 0
    }

    @Test func deletesOnlyAFileItsCheckAccepts() throws {
        let directory = try TemporaryDirectory()
        let accepted = try directory.file("accepted", contents: Data("a".utf8))
        let refused = try directory.file("refused", contents: Data("b".utf8))

        for file in [accepted, refused] {
            try item(file).deleteFile(ownedBy: getuid(), ofAtMost: 16) { $0 == Data("a".utf8) }
        }

        #expect(accepted.isMissing)
        #expect(refused.isThere)
    }

    @Test func keepsAFileOfAnotherOwner() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("file", contents: Data("a".utf8))

        try item(file).deleteFile(ownedBy: getuid() + 1, ofAtMost: 16) { _ in true }

        #expect(file.isThere)
    }

    @Test func keepsAFileLargerThanItReads() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("file", contents: Data("12345".utf8))

        try item(file).deleteFile(ownedBy: getuid(), ofAtMost: 4) { _ in true }

        #expect(file.isThere)
    }

    @Test func keepsALinkAndWhatItLeadsTo() throws {
        let directory = try TemporaryDirectory()
        let target = try directory.file("target", contents: Data("a".utf8))
        let link = directory.url.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try item(link).deleteFile(ownedBy: getuid(), ofAtMost: 16) { _ in true }

        #expect(link.isThere)
        #expect(target.isThere)
    }

    @Test func deletesNothingButTheFileItJudged() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("file", contents: Data("kept".utf8))
        let opened = try item(file)
        let aside = directory.url.appending(path: "aside")
        let judged = try directory.file("judged", contents: Data("a".utf8))
        try #require(move(file, to: aside))
        try #require(move(judged, to: file))

        opened.deleteFile(ownedBy: getuid(), ofAtMost: 16) { bytes in
            move(aside, to: file) && bytes == Data("a".utf8)
        }

        #expect([file, aside].contains { (try? Data(contentsOf: $0)) == Data("kept".utf8) })
    }

    @Test func keepsAFileThatTookTheNameWhileItWasRead() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("file", contents: Data("a".utf8))
        let other = try directory.file("other", contents: Data("a".utf8))

        try item(file).deleteFile(ownedBy: getuid(), ofAtMost: 16) { _ in move(other, to: file) }

        #expect(file.isThere)
        #expect(other.isMissing)
    }
}
