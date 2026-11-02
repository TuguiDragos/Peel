import Darwin
import Foundation
@testable import PeelCore
import Synchronization
import Testing

private final class Started: Sendable {
    private let labels = Mutex<[String]>([])

    func add(_ label: String) { labels.withLock { $0.append(label) } }

    var all: [String] { labels.withLock { $0 } }
}

/// A made-up home with an agent's file moved to its own Trash, and an edit written in its place.
private struct EditedAgent: ~Copyable {
    let directory: TemporaryDirectory
    let place: URL
    let trash: URL
    let started = Started()

    init() throws {
        let directory = try TemporaryDirectory()
        let place = try directory.file("home/Library/LaunchAgents/org.example.edit.plist", contents: Data("old".utf8))
        let trash = try directory.directory("home/.Trash")
        self.place = place
        self.trash = trash
        self.directory = directory
    }

    func service(exclusions: Exclusions = .none) -> TrashService {
        let trash = trash
        let started = started
        return TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            exclusions: exclusions,
            startJob: { job, _ in started.add(job.label) }
        ) { url in
            var destination = trash.appending(path: url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                destination = trash.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
            }
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    /// Moves the file at its place to the Trash, as a Save does, and writes `edit` there instead.
    func edit(_ edit: String, with service: TrashService) async throws -> TrashedItem {
        var moved = try #require(await service.trash([place]).trashed.first)
        try Data(edit.utf8).write(to: place)
        moved.replacedBy = TrashedItem.Identity(ofItemAt: place)
        return moved
    }

    func text(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

struct EditPutBackTests {
    @Test func aRecordKeepsWhatAnEditWroteInItsPlace() throws {
        let directory = try TemporaryDirectory()
        let edit = try directory.file("org.example.edit.plist", bytes: 3)
        let item = TrashedItem(
            originalURL: URL(filePath: "/Users/x/Library/LaunchAgents/org.example.edit.plist"),
            trashedURL: URL(filePath: "/Users/x/.Trash/org.example.edit.plist"), date: .now
        )
        var edited = item
        edited.replacedBy = TrashedItem.Identity(ofItemAt: edit)
        #expect(edited.replacedBy != nil)
        let record = RemovalRecord(batch: UUID(), item: edited, size: 3, source: "org.example.edit", tool: "backgroundItems")

        let read = try JSONDecoder().decode(RemovalRecord.self, from: JSONEncoder().encode(record))
        let older = try JSONDecoder().decode(
            RemovalRecord.self,
            from: JSONEncoder().encode(RemovalRecord(batch: UUID(), item: item, size: 3, source: "x", tool: "y"))
        )

        #expect(read.trashedItem.replacedBy == edited.replacedBy)
        #expect(older.trashedItem.replacedBy == nil)
    }

    @Test func putBackRefusesAPlaceTakenByAnythingButTheEditItRecords() async throws {
        let agent = try EditedAgent()
        let service = agent.service()
        let moved = try await agent.edit("edited", with: service)
        var unrecorded = moved
        unrecorded.replacedBy = nil
        var another = moved
        another.replacedBy = TrashedItem.Identity(ofItemAt: agent.trash)

        #expect(moved.replacementStandsInItsPlace)
        #expect(service.refusal(ofPuttingBack: moved, canUseHelper: false) == nil)
        #expect(service.refusal(ofPuttingBack: unrecorded, canUseHelper: false) == .alreadyThere)
        #expect(service.refusal(ofPuttingBack: another, canUseHelper: false) == .alreadyThere)
    }

    @Test func putBackMovesTheEditToTheTrashFirstThenPutsTheOldFileBackAndStartsItsJob() async throws {
        let agent = try EditedAgent()
        let service = agent.service()
        var moved = try await agent.edit("edited", with: service)
        moved.stoppedJob = "org.example.edit"

        let result = await service.restore([moved])

        #expect(result.failures == [nil])
        let aside = try #require(result.movedAside.first ?? nil)
        #expect(aside.originalURL == agent.place)
        #expect(try agent.text(at: agent.place) == "old")
        #expect(try agent.text(at: aside.trashedURL) == "edited")
        #expect(aside.replacedBy == moved.identity)
        #expect(aside.replacementStandsInItsPlace)
        #expect(agent.started.all.isEmpty, "the file holds no job launchd could read, so none starts")

        let again = await service.restore([aside])
        #expect(again.failures == [nil])
        #expect(try agent.text(at: agent.place) == "edited")
        let back = try #require(again.movedAside.first ?? nil)
        #expect(try agent.text(at: back.trashedURL) == "old")
    }

    @Test func startsTheJobTheOldFileDeclaresOnceItIsBack() async throws {
        let agent = try EditedAgent()
        let job = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>Label</key><string>org.example.edit</string>
            <key>ProgramArguments</key><array><string>/bin/sleep</string><string>1</string></array></dict></plist>
            """
        try Data(job.utf8).write(to: agent.place)
        let service = agent.service()
        var moved = try await agent.edit("edited", with: service)
        moved.stoppedJob = "org.example.edit"

        #expect(await service.restore([moved]).failures == [nil])
        #expect(agent.started.all == ["org.example.edit"])
    }

    @Test func movesNothingWhenTheEditCannotGoToTheTrash() async throws {
        let agent = try EditedAgent()
        let service = agent.service()
        let moved = try await agent.edit("edited", with: service)
        #expect(chflags(agent.place.path(percentEncoded: false), UInt32(UF_IMMUTABLE)) == 0)
        defer { _ = chflags(agent.place.path(percentEncoded: false), 0) }

        let result = await service.restore([moved])

        #expect(result.failures == [.replacementStays(.locked)])
        #expect(result.movedAside == [nil])
        #expect(try agent.text(at: agent.place) == "edited")
        #expect(try agent.text(at: moved.trashedURL) == "old")
        #expect(service.refusal(ofPuttingBack: moved, canUseHelper: false) == .replacementStays(.locked))
    }

    @Test func putsTheEditBackWhenTheOldFileCannotGoBack() async throws {
        let agent = try EditedAgent()
        let service = agent.service()
        let moved = try await agent.edit("edited", with: service)
        // The old file left the Trash meanwhile, so it can't go back.
        try FileManager.default.removeItem(at: moved.trashedURL)
        try Data("old".utf8).write(to: moved.trashedURL)

        let result = await service.restore([moved])

        #expect(result.failures == [.missingFromTrash])
        #expect(result.movedAside == [nil])
        #expect(try agent.text(at: agent.place) == "edited")
    }
}
