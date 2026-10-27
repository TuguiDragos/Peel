import Foundation
import PeelPrivileged
import Testing

struct DamagedFileTests {
    @Test func setsAFileAsideWithoutReplacingOneSetAsideBefore() throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("Peel/removals.json", contents: Data("damaged".utf8))
        let stamp = DateFormatter()
        stamp.calendar = Calendar(identifier: .gregorian)
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        let now = Date.now
        let taken = try (0..<3).map { second in
            let name = "removals-damaged-\(stamp.string(from: now.addingTimeInterval(Double(second)))).json"
            return try directory.file("Peel/\(name)", contents: Data("earlier".utf8))
        }

        let aside = try #require(DamagedFile.setAside(url))

        #expect(aside.lastPathComponent.wholeMatch(of: /removals-damaged-\d{4}-\d{2}-\d{2}-\d{6}-2\.json/) != nil)
        #expect(try String(contentsOf: aside, encoding: .utf8) == "damaged")
        #expect(try taken.allSatisfy { try String(contentsOf: $0, encoding: .utf8) == "earlier" })
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func findsOnlyTheCopiesItMade() throws {
        let directory = try TemporaryDirectory()
        let made = try directory.file("Peel/refusals-damaged-2026-10-01-090000.json")
        let again = try directory.file("Peel/refusals-damaged-2026-10-01-090000-2.json")
        try directory.file("Peel/refusals-damaged-by-hand.json")
        try directory.file("Peel/removals-damaged-2026-10-01-090000.json")
        try directory.file("Peel/refusals-damaged-2026-10-01-090000.json.bak")
        try directory.directory("Peel/refusals-damaged-2026-10-02-090000.json")

        let copies = try #require(DamagedFile.copies(of: directory.url.appending(path: "Peel/refusals.json")))

        #expect(Set(copies.map(\.lastPathComponent)) == [made.lastPathComponent, again.lastPathComponent])
        #expect(copies.allSatisfy { $0.deletingLastPathComponent().lastPathComponent == "Peel" })
        #expect(DamagedFile.copies(of: directory.url.appending(path: "Missing/refusals.json")) == [])
    }

    @Test(.permissionsHold) func saysWhenItCannotLookForCopies() throws {
        let directory = try TemporaryDirectory()
        let url = try directory.directory("Peel").appending(path: "refusals.json")
        try directory.setPermissions(0o300, of: "Peel")
        defer { try? directory.setPermissions(0o700, of: "Peel") }

        #expect(DamagedFile.copies(of: url) == nil)
    }

    @Test func answersNothingForAFileThatIsNotThere() throws {
        let directory = try TemporaryDirectory()
        #expect(DamagedFile.setAside(directory.url.appending(path: "missing.json")) == nil)
    }
}
