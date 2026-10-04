import Foundation
@testable import PeelCore
import Testing

struct PathPatternTests {
    @Test func resolvesPlainPathsAgainstTheHomeItIsGiven() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Caches/tool/file", bytes: 16)

        #expect(PathPattern.expand("Library/Caches/tool", home: directory.url).count == 1)
        #expect(PathPattern.expand("~/Library/Caches/tool", home: directory.url).count == 1)
        #expect(PathPattern.expand("Library/Caches/missing", home: directory.url).isEmpty)
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

        let matches = PathPattern.expand(".virtualenvs/*/", home: directory.url).map { $0.path(percentEncoded: false) }

        #expect(Set(matches) == Set([web, link].map(PathPattern.comparablePath(of:))))
        #expect(
            PathPattern.expand(".virtualenvs/web/", home: directory.url).map { $0.path(percentEncoded: false) } == [
                PathPattern.comparablePath(of: web)
            ]
        )
    }

    @Test func expandsWildcardsIntoEveryFolderThatExists() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Library/Caches/Google/AndroidStudio2026.1")
        try directory.directory("Library/Caches/Google/AndroidStudio2026.2")
        try directory.directory("Library/Caches/Google/Chrome")

        let matches = PathPattern.expand("Library/Caches/Google/AndroidStudio*", home: directory.url)
        #expect(matches.map(\.lastPathComponent).sorted() == ["AndroidStudio2026.1", "AndroidStudio2026.2"])
    }

    @Test func stopsAtTheMatchLimit() throws {
        let directory = try TemporaryDirectory()
        for index in 0..<5 {
            try directory.directory("Library/Caches/tool/run-\(index)")
        }

        #expect(PathPattern.expand("Library/Caches/tool/run-*", home: directory.url, maximum: 2).count == 2)
    }

    /// At its limit, `glob` returns `GLOB_NOSPACE` along with the paths found so far. Those paths are kept, so a
    /// folder with more entries than the limit still lists what was found.
    @Test func keepsWhatWasFoundWhenThereIsMoreThanTheLimit() throws {
        let directory = try TemporaryDirectory()
        for index in 0..<300 {
            try directory.directory("Library/Caches/tool/run-\(index)")
        }

        let matches = PathPattern.expand("Library/Caches/tool/run-*", home: directory.url)
        #expect(!matches.isEmpty)
        #expect(matches.count <= PathPattern.maximumMatches)
        #expect(Set(matches).count == matches.count)
    }

    /// A bracket in a real name is not a character class: `App [Beta]` has to find itself.
    @Test func findsAFolderWhoseNameHoldsABracket() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Library/Caches/App [Beta]")

        #expect(PathPattern.expand("Library/Caches/App [Beta]", home: directory.url).map(\.lastPathComponent) == ["App [Beta]"])
    }
}
