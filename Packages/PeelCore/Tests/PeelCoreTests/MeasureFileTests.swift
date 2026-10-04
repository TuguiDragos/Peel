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
}
