import Foundation
@testable import PeelCore
import Testing

struct LeftForAnAdministratorTests {
    private func record(
        _ url: URL, app: String = "Scribbler", confidence: MatchConfidence = .certain
    ) -> LeftForAnAdministrator.Record {
        LeftForAnAdministrator.Record(
            path: PathPattern.comparablePath(of: url),
            kind: .library,
            apps: [.init(reference: "org.example.\(app.lowercased())", name: app)],
            reason: confidence == .possible ? .vendorPrefix : .bundleIdentifier,
            confidence: confidence
        )
    }

    @Test func keepsWhatItIsGivenAndForgetsWhatIsGone() async throws {
        let directory = try TemporaryDirectory()
        let memory = LeftForAnAdministrator(url: directory.url.appending(path: "left.json"))
        let kept = try directory.directory("root/Library/org.example.kept")
        let removed = try directory.directory("root/Library/org.example.removed")

        await memory.record([record(kept), record(removed)])
        #expect(await memory.load() == [record(kept), record(removed)])

        try FileManager.default.removeItem(at: removed)
        let later = try directory.directory("root/Library/org.example.later")
        await memory.record([record(later)])

        #expect(await memory.load() == [record(kept), record(later)])
    }

    @Test func theRecordsOfOneItemBecomeOneKeepingTheSurerClaim() async throws {
        let directory = try TemporaryDirectory()
        let memory = LeftForAnAdministrator(url: directory.url.appending(path: "left.json"))
        let shared = try directory.directory("root/Library/org.example.shared")
        let first = record(shared, app: "First")
        let spelledElsewhere = LeftForAnAdministrator.Record(
            path: "/private" + first.path, kind: first.kind, apps: first.apps, reason: first.reason,
            confidence: first.confidence
        )
        #expect(first.path.hasPrefix("/var/"), "the temporary folder is not under /var, so /private names it no other way")
        let sure = try directory.directory("root/Library/org.example.sure")
        let hinted = try directory.directory("root/Library/org.example.hinted")

        await memory.record([spelledElsewhere, record(sure, app: "Sure"), record(hinted, app: "Hint", confidence: .possible)])
        await memory.record([
            record(shared, app: "Second"), record(sure, app: "Hint", confidence: .possible), record(hinted, app: "Sure"),
        ])

        let loaded = await memory.load()
        #expect(loaded.count == 3)
        #expect(loaded.first { $0.path.hasSuffix("org.example.shared") }?.apps.map(\.name) == ["First", "Second"])
        #expect(loaded.first { $0.path.hasSuffix("org.example.sure") } == record(sure, app: "Sure"))
        #expect(loaded.first { $0.path.hasSuffix("org.example.hinted") } == record(hinted, app: "Sure"))
    }

    @Test func readingLeavesAHomeAsItFoundIt() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "Peel/left.json")

        #expect(await LeftForAnAdministrator(url: url).load().isEmpty)
        #expect(url.deletingLastPathComponent().isMissing)
    }

    @Test(.permissionsHold) func leavesAFileItCannotReadAlone() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "left.json")
        let memory = LeftForAnAdministrator(url: url)
        await memory.record([record(try directory.directory("root/Library/org.example.one"))])
        let before = try Data(contentsOf: url)
        try directory.setPermissions(0o000, of: "left.json")
        defer { try? directory.setPermissions(0o644, of: "left.json") }

        await memory.record([record(try directory.directory("root/Library/org.example.two"))])

        try directory.setPermissions(0o644, of: "left.json")
        #expect(try Data(contentsOf: url) == before, "a file that could not be read was written over")
    }

    @Test func aDamagedFileIsSetAsideAndWhatCanBeReadOfItKept() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "left.json")
        let folder = try directory.directory("root/Library/org.example.one")
        let encoder = JSONEncoder()
        let good = try #require(String(data: try encoder.encode(record(folder)), encoding: .utf8))
        try Data("[\(good), {\"path\": 7}]".utf8).write(to: url)

        #expect(await LeftForAnAdministrator(url: url).load() == [record(folder)])
        let set = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false))
        #expect(set.contains { $0.contains("damaged") }, "the file as it was is not kept: \(set)")
    }
}
