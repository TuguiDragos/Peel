import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct SelectionCarrierTests {
    private final class OpenApps: CarriesSelection {
        let openApps: [String: String]
        init(_ openApps: [String: String]) { self.openApps = openApps }
        var carriedParts: [CarriedSelection.Part] { [] }
        func appToQuit(for part: CarriedSelection.Part) -> String? { openApps[part.page.scope] }
        func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? { nil }
        func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {}
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
}
