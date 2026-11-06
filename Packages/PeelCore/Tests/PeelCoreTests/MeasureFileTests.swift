import Foundation
@testable import PeelCore
import Testing

struct MeasureFileTests {
    @Test func takesAFileNameAndNeverAPath() throws {
        let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)
        for refused in ["", "/tmp/report.txt", "Logs/report.txt", "../report.txt", ".report", "."] {
            #expect(MeasureFile(named: refused, home: home) == nil, "\(refused.debugDescription) was taken")
        }
        let file = try #require(MeasureFile(named: "report.txt", home: home))
        #expect(file.url.path(percentEncoded: false) == "/Users/x/Library/Logs/Peel/report.txt")
    }

    @Test func appendsEachReport() throws {
        let directory = try TemporaryDirectory()
        let file = try #require(MeasureFile(named: "report.txt", home: directory.url))

        file.append(["first frame: 10.0 ms after exec"])
        file.append(["run loop: 3 turns"])

        #expect(try String(contentsOf: file.url, encoding: .utf8) == "first frame: 10.0 ms after exec\nrun loop: 3 turns\n")
    }

    /// Peel may hold rights its launcher lacks, so a link put at the report's name is never written through.
    @Test func neverWritesThroughALink() throws {
        let directory = try TemporaryDirectory()
        let target = try directory.file("Elsewhere/data.db", contents: Data("kept".utf8))
        try directory.directory("Library/Logs/Peel")
        try FileManager.default.createSymbolicLink(at: directory.url.appending(path: "Library/Logs/Peel/report.txt"), withDestinationURL: target)
        let file = try #require(MeasureFile(named: "report.txt", home: directory.url))

        file.append(["run loop: 3 turns"])

        #expect(try String(contentsOf: target, encoding: .utf8) == "kept")
    }

    /// Nor is a link put at a folder on the way: nothing is made or written through it.
    @Test func neverWritesThroughALinkedFolder() throws {
        for linked in ["Library/Logs", "Library/Logs/Peel"] {
            let directory = try TemporaryDirectory()
            let elsewhere = try directory.directory("Elsewhere")
            try directory.directory((linked as NSString).deletingLastPathComponent)
            try FileManager.default.createSymbolicLink(
                at: directory.url.appending(path: linked), withDestinationURL: elsewhere
            )
            let file = try #require(MeasureFile(named: "report.txt", home: directory.url))

            file.append(["run loop: 3 turns"])

            let left = try FileManager.default.contentsOfDirectory(atPath: elsewhere.path(percentEncoded: false))
            #expect(left.isEmpty, "\(linked) was written through: \(left)")
        }
    }
}
