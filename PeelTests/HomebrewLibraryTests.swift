import Foundation
import Observation
@testable import Peel
@testable import PeelCore
import Testing

@Suite(.serialized) struct HomebrewLibraryTests {
    @Test func namesInHistoryOnlyTheCasksWhoseRecordMoved() throws {
        let caskroom = URL(filePath: "/opt/homebrew/Caskroom", directoryHint: .isDirectory)
        let casks = ["alpha", "beta", "gamma"].map { HomebrewPackage(name: $0, kind: .cask).kept(inCaskroom: caskroom) }
        let folder = try #require(casks[0].caskroomFolder)
        let trashed = TrashedItem(originalURL: folder, trashedURL: URL(filePath: "/Users/me/.Trash/alpha"), date: .now)

        #expect(HomebrewLibrary.source(of: casks, after: TrashResult(trashed: [trashed])).source == "alpha")
        #expect(HomebrewLibrary.source(of: casks, after: TrashResult()).source == "alpha, beta, gamma")
    }

    @Test func readsHomebrewAgainOnceItCheckedForNewVersions() async {
        guard Homebrew.executableURL != nil, await Homebrew.hasLocalDefinitions() else { return }
        let homebrew = HomebrewLibrary()
        await homebrew.refresh()
        let read = homebrew.revision
        let checked = await Homebrew.lastUpdateCheck()

        #expect(await !homebrew.readAgain(ifHomebrewCheckedAt: checked))
        #expect(homebrew.revision == read)
        #expect(await homebrew.readAgain(ifHomebrewCheckedAt: (checked ?? .now) + 1))
        #expect(homebrew.revision == read + 1)
    }

    @Test func homebrewsOwnWorkEndsBeforePeelReadsWhatItChanged() async {
        guard Homebrew.executableURL != nil, await Homebrew.hasLocalDefinitions() else { return }
        // Nothing is read yet, so Upgrade All finds nothing to upgrade and runs no `brew upgrade`.
        let homebrew = HomebrewLibrary()

        let seen = await shownWhenTheReadingStarts(of: homebrew) { await homebrew.run(.upgradeAll, showsResult: false) }

        #expect(seen?.progress == nil)
        #expect(seen?.command == nil)
        #expect(seen?.isReading == true)
        #expect(seen?.isBusy == true)
        #expect(homebrew.runningCommand == nil && !homebrew.isReadingWhatChanged && homebrew.progress == nil)
    }

    @Test func forgetsMovesEndBeforePeelReadsWhatChanged() async {
        guard Homebrew.executableURL != nil, await Homebrew.hasLocalDefinitions() else { return }
        let homebrew = HomebrewLibrary()
        // A made-up cask has no folder in the Caskroom, so nothing moves.
        let cask = HomebrewPackage(name: "org-example-gone", kind: .cask, installedVersion: "1.0")

        let seen = await shownWhenTheReadingStarts(of: homebrew) { _ = await homebrew.forget([cask]) { _ in } }

        #expect(seen?.forgetting.isEmpty == true)
        #expect(seen?.isReading == true)
        #expect(seen?.isBusy == true)
        #expect(!homebrew.isForgetting && !homebrew.isReadingWhatChanged)
    }

    private struct Shown {
        let progress: String?
        let command: HomebrewLibrary.Command?
        let forgetting: Set<HomebrewPackage.ID>
        let isReading: Bool
        let isBusy: Bool
    }

    @MainActor private final class Seen {
        var shown: Shown?
    }

    /// What `homebrew` shows at the moment its reading starts while `work` runs.
    private func shownWhenTheReadingStarts(
        of homebrew: HomebrewLibrary,
        during work: () async -> Void
    ) async -> Shown? {
        let seen = Seen()
        withObservationTracking {
            _ = homebrew.isScanning
        } onChange: {
            MainActor.assumeIsolated {
                seen.shown = Shown(
                    progress: homebrew.progress, command: homebrew.commandHomebrewRuns,
                    forgetting: homebrew.casksBeingForgotten, isReading: homebrew.isReadingWhatChanged,
                    isBusy: homebrew.runningCommand != nil || homebrew.isForgetting
                )
            }
        }
        await work()
        return seen.shown
    }
}
