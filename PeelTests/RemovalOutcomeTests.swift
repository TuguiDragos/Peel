import Foundation
@testable import Peel
import PeelCore
import Testing

struct RemovalOutcomeTests {
    @Test func tellsOfShellFilesThatStillNameWhatMoved() {
        let outcome = RemovalOutcome()
        let reference = ShellReferences.Reference(file: URL(filePath: "/Users/me/.zshrc"), line: 12)

        outcome.report(TrashResult(), shellReferences: [reference])
        #expect(!outcome.isEmpty && outcome.shellReferences == [reference])
        outcome.report(TrashResult())
        #expect(outcome.shellReferences == [reference], "a removal with nothing to tell changes nothing")

        outcome.clear()
        #expect(outcome.isEmpty)
    }

    @Test func tellsOfARemovalHistoryCouldNotRecord() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let peel = folder.appending(path: "Peel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: peel, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: peel.appending(path: "removals.json"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: peel.path(percentEncoded: false)
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: peel.path(percentEncoded: false)
            )
            try? FileManager.default.removeItem(at: folder)
        }
        let outcome = RemovalOutcome()
        let history = RemovalHistoryStore(
            log: RemovalLog(url: peel.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            outcome: outcome
        )
        let item = #"{"originalURL": "file:///Users/me/Cache", "trashedURL": "file:///Users/me/.Trash/Cache", "date": 0}"#
        let moved = try JSONDecoder().decode(TrashedItem.self, from: Data(item.utf8))

        await history.record(TrashResult(trashed: [moved]), tool: .developer, source: "Xcode", sizes: [:])

        #expect(outcome.historyCouldNotRecord && !outcome.isEmpty)
        #expect(RemovalFailureAlert.message(for: outcome).hasPrefix("What moved is in the Trash"))
        #expect(RemovalFailureAlert.details(for: outcome).hasPrefix("What moved is in the Trash"))
    }
}
