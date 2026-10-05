import Foundation
@testable import PeelCore
import Testing

struct PathPatternTests {
    @Test func resolvesPlainPathsAgainstTheHomeItIsGiven() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Caches/tool/file", bytes: 16)

        #expect(PathPattern.expand("Library/Caches/tool", home: directory.url, from: .peel).count == 1)
        #expect(PathPattern.expand("~/Library/Caches/tool", home: directory.url, from: .peel).count == 1)
        #expect(PathPattern.expand("Library/Caches/missing", home: directory.url, from: .peel).isEmpty)
    }

    /// A pattern that ends in `/` matches folders only, and each comes back named as the entry itself, without the
    /// slash, so a link among them is a link and not the folder it leads to.
    @Test func aPatternEndingInASlashMatchesFoldersByTheirOwnNames() throws {
        let directory = try TemporaryDirectory()
        let web = try directory.directory(".virtualenvs/web")
        try directory.file(".virtualenvs/postactivate")
        let elsewhere = try directory.directory("Volumes/Fast/env")
        let link = directory.url.appending(path: ".virtualenvs/fast")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)

        let matches = PathPattern.expand(".virtualenvs/*/", home: directory.url, from: .peel).map { $0.path(percentEncoded: false) }

        #expect(Set(matches) == Set([web, link].map(PathPattern.comparablePath(of:))))
        #expect(
            PathPattern.expand(".virtualenvs/web/", home: directory.url, from: .peel).map { $0.path(percentEncoded: false) } == [
                PathPattern.comparablePath(of: web)
            ]
        )
    }

    @Test func expandsWildcardsIntoEveryFolderThatExists() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Library/Caches/Google/AndroidStudio2026.1")
        try directory.directory("Library/Caches/Google/AndroidStudio2026.2")
        try directory.directory("Library/Caches/Google/Chrome")

        let matches = PathPattern.expand("Library/Caches/Google/AndroidStudio*", home: directory.url, from: .peel)
        #expect(matches.map(\.lastPathComponent).sorted() == ["AndroidStudio2026.1", "AndroidStudio2026.2"])
    }

    /// A cask's pattern stops where `glob` does, keeping the paths found by then, and Peel's own finds every match.
    @Test func onlyACasksPatternStopsAtGlobsLimit() throws {
        let directory = try TemporaryDirectory()
        for index in 0..<300 {
            try directory.directory("Library/Caches/tool/run-\(index)")
        }

        let limited = PathPattern.expand("Library/Caches/tool/run-*", home: directory.url, from: .cask)
        let whole = PathPattern.expand("Library/Caches/tool/run-*", home: directory.url, from: .peel)

        #expect(limited.count == 128)
        #expect(Set(limited).count == limited.count)
        #expect(whole.count == 300)
    }

    /// A bracket in a real name is not a character class: `App [Beta]` has to find itself.
    @Test func findsAFolderWhoseNameHoldsABracket() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Library/Caches/App [Beta]")

        #expect(PathPattern.expand("Library/Caches/App [Beta]", home: directory.url, from: .peel).map(\.lastPathComponent) == ["App [Beta]"])
    }
}
