import Foundation
@testable import PeelCore
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

    @Test func answersNothingForAFileThatIsNotThere() throws {
        let directory = try TemporaryDirectory()
        #expect(DamagedFile.setAside(directory.url.appending(path: "missing.json")) == nil)
    }
}
