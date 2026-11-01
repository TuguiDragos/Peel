import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct SelectionCarrierTests {
    private final class OpenApps: CarriesSelection {
        var isRemoving = false
        let openApps: [String: String]
        init(_ openApps: [String: String]) { self.openApps = openApps }
        var carriedParts: [CarriedSelection.Part] { [] }
        func appToQuit(for part: CarriedSelection.Part) -> String? { openApps[part.page.scope] }
        func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? { nil }
        func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {}
        func deselect(_ part: CarriedSelection.Part) {}
    }

    /// A tool that moves each part at once and notes the removal its moves were written down under.
    private final class Recording: CarriesSelection {
        var isRemoving = false
        var seen: [RecordedRemoval?] = []
        var carriedParts: [CarriedSelection.Part] { [] }
        func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
            seen.append(RecordedRemoval.current)
            let name = part.page.scope
            let json = #"{"originalURL": "file:///Users/me/\#(name)", "trashedURL": "file:///Users/me/.Trash/\#(name)", "date": 0}"#
            let item = try? JSONDecoder().decode(TrashedItem.self, from: Data(json.utf8))
            return TrashResult(trashed: [item].compactMap(\.self))
        }
        func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {}
        func deselect(_ part: CarriedSelection.Part) {}
    }

    /// A tool that notes, at each step of a pass, whether it and `other` count as removing.
    private final class Watching: CarriesSelection {
        var isRemoving = false
        var other: Watching?
        var seen: [Bool] = []
        var carriedParts: [CarriedSelection.Part] { [] }
        func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
            seen += [isRemoving, other?.isRemoving ?? true]
            return TrashResult()
        }
        func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
            seen += [isRemoving, other?.isRemoving ?? true]
        }
        func deselect(_ part: CarriedSelection.Part) {}
    }

    private func part(_ scope: String) -> CarriedSelection.Part {
        CarriedSelection.Part(
            page: Tool.developer.page(scope), title: scope, source: scope, sourceKey: nil,
            sizes: [URL(filePath: "/Users/me/Library/Caches/\(scope)"): 4_096]
        )
    }

    @Test func namesEveryOpenAppThatKeepsAPart() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let carrier = SelectionCarrier(
            tools: [.developer: OpenApps(["chrome": "Google Chrome", "slack": "Slack"])],
            apps: AppLibrary(
                defaults: made.defaults, releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "notes.json"))
            ),
            history: RemovalHistoryStore(
                log: RemovalLog(url: folder.appending(path: "removals.json")),
                refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
                knowsTheExclusions: { true }
            ),
            outcome: RemovalOutcome()
        )

        let kept = carrier.kept(among: [part("chrome"), part("npm"), part("slack")])

        #expect(kept.map(\.app) == ["Google Chrome", "Slack"])
        #expect(kept.map(\.part.page.scope) == ["chrome", "slack"])
        #expect(carrier.free(among: [part("chrome"), part("npm"), part("slack")]).map(\.page.scope) == ["npm"])
    }

    @Test func movesEachPartAsPartOfTheRemovalHistoryRecords() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let recording = Recording()
        let log = RemovalLog(url: folder.appending(path: "removals.json"))
        let carrier = SelectionCarrier(
            tools: [.developer: recording],
            apps: AppLibrary(
                defaults: made.defaults, releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "notes.json"))
            ),
            history: RemovalHistoryStore(
                log: log,
                refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
                knowsTheExclusions: { true }
            ),
            outcome: RemovalOutcome()
        )

        await carrier.move([part("npm"), part("pip")])

        let batch = try #require(await log.load().records?.first?.batch)
        #expect(recording.seen.map { $0?.batch } == [batch, batch])
        #expect(recording.seen.map { $0?.part } == [part("npm").removalPart, part("pip").removalPart])
    }

    @Test func everyToolOfAPassCountsAsRemovingUntilTheLastIsUpToDate() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let (developer, space, orphans) = (Watching(), Watching(), Watching())
        developer.other = space
        space.other = developer
        let carrier = SelectionCarrier(
            tools: [.developer: developer, .space: space, .orphans: orphans],
            apps: AppLibrary(
                defaults: made.defaults, releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "notes.json"))
            ),
            history: RemovalHistoryStore(
                log: RemovalLog(url: folder.appending(path: "removals.json")),
                refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
                knowsTheExclusions: { true }
            ),
            outcome: RemovalOutcome()
        )
        let logs = CarriedSelection.Part(
            page: Tool.space.page("logs"), title: "Logs", source: "Logs", sourceKey: nil,
            sizes: [URL(filePath: "/Users/me/Library/Logs/org.example"): 4_096]
        )

        await carrier.move([part("npm"), logs, part("pip")])

        #expect(developer.seen == Array(repeating: true, count: 6))
        #expect(space.seen == Array(repeating: true, count: 4))
        #expect(!developer.isRemoving && !space.isRemoving)
        #expect(orphans.seen.isEmpty && !orphans.isRemoving)
    }
}
