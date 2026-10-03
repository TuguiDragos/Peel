import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// Peel tells the user when an app lands in the Trash, since it may have left files behind, but not when Peel
/// moved the app there itself.
struct OwnTrashMovesTests {
    private let trash = URL(filePath: "/Users/x/.Trash", directoryHint: .isDirectory)

    private func watched() -> OwnTrashMoves {
        let moves = OwnTrashMoves()
        moves.whenSettled {}
        return moves
    }

    /// The Trash renames an item whose name is taken, so Peel's own move can land as `Foo 2.app` beside the
    /// `Foo.app` already there. What counts is where it landed, not the name it had.
    @Test func anAppPeelMovedIsNotToldUnderTheNameItLandedWith() {
        let moves = watched()
        let look = moves.look()
        moves.began()
        moves.ended(landedAt: [trash.appending(path: "Foo 2.app")])

        #expect(moves.arrivals(["Foo.app", "Foo 2.app", "Bar.app"], known: ["Foo.app"], in: trash, since: look) == ["Bar.app"])
    }

    /// A move that fails lands nothing, so it keeps nothing from being told: the user moving that app to the
    /// Trash later is still told.
    @Test func aMoveThatLandedNothingSilencesNothing() {
        let moves = OwnTrashMoves()
        moves.began()
        moves.ended(landedAt: [])

        #expect(moves.arrivals(["Foo.app"], known: [], in: trash, since: moves.look()) == ["Foo.app"])
    }

    /// While a move of Peel's own is under way, where its items land is not known yet, so nothing is told and
    /// the look does not count. Its end says to look again.
    @Test func looksAgainOnceItsOwnMoveHasEnded() {
        let moves = OwnTrashMoves()
        let settled = Mutex(0)
        moves.whenSettled { settled.withLock { $0 += 1 } }

        moves.began()
        #expect(moves.arrivals(["Foo.app"], known: [], in: trash, since: moves.look()) == nil)
        moves.began()
        moves.ended(landedAt: [])
        #expect(settled.withLock { $0 } == 0, "one move is still under way")
        moves.ended(landedAt: [trash.appending(path: "Foo.app")])
        #expect(settled.withLock { $0 } == 1)
        #expect(moves.arrivals(["Foo.app"], known: [], in: trash, since: moves.look()) == [])
    }

    /// What Peel landed is forgotten once a look that began after it has run: the item was seen, or it has left
    /// the Trash since. The same name moved there later by the user is then told.
    @Test func forgetsWhatItLandedOnceALookHasSeenIt() {
        let moves = watched()
        moves.began()
        moves.ended(landedAt: [trash.appending(path: "Foo.app")])
        let first = moves.look()
        #expect(moves.arrivals(["Foo.app"], known: [], in: trash, since: first) == [])

        // Emptied, then the user moves another copy of Foo there.
        #expect(moves.arrivals([], known: ["Foo.app"], in: trash, since: moves.look()) == [])
        #expect(moves.arrivals(["Foo.app"], known: [], in: trash, since: moves.look()) == ["Foo.app"])
    }

    /// Each Trash is looked at on its own, so a look at one keeps what landed in another until that one is seen.
    @Test func aLookAtOneTrashKeepsWhatLandedInAnother() {
        let moves = watched()
        let volume = URL(filePath: "/Volumes/Disk/.Trashes/501", directoryHint: .isDirectory)
        moves.began()
        moves.ended(landedAt: [volume.appending(path: "Foo.app")])

        #expect(moves.arrivals([], known: [], in: trash, since: moves.look()) == [])
        let arrived = moves.arrivals(["Foo.app"], known: [], in: volume, since: moves.look())
        #expect(arrived == [], "Peel's own app was told")
    }

    /// A listing that began before Peel's move landed may not show what it landed, so what landed after the
    /// look began is kept for the next one.
    @Test func keepsWhatLandedAfterTheLookBegan() {
        let moves = watched()
        let look = moves.look()
        moves.began()
        moves.ended(landedAt: [trash.appending(path: "Foo.app")])

        #expect(moves.arrivals([], known: [], in: trash, since: look) == [])
        #expect(moves.arrivals(["Foo.app"], known: [], in: trash, since: moves.look()) == [], "Peel's own app was told")
    }

    /// Every removal goes through `TrashService`, so every tool's moves are Peel's own, whichever page made them.
    @Test func everyMoveThroughTheTrashServiceIsPeelsOwn() async {
        let moves = watched()
        let environment = SearchEnvironment(homeDirectory: URL(filePath: "/Users/x"), rootDirectory: URL(filePath: "/"))
        let service = TrashService(environment: environment, ownMoves: moves) { [trash] _ in trash.appending(path: "Install macOS 2.app") }

        _ = await service.trash([URL(filePath: "/Users/x/Downloads/Install macOS.app")])

        #expect(moves.arrivals(["Install macOS 2.app"], known: [], in: trash, since: 0) == [])
    }

    @Test func keepsNothingWhileNobodyWatches() {
        let moves = OwnTrashMoves()
        moves.began()
        moves.ended(landedAt: [trash.appending(path: "Foo.app")])
        moves.whenSettled {}
        #expect(moves.arrivals(["Foo.app"], known: [], in: trash, since: moves.look()) == ["Foo.app"])

        moves.began()
        moves.ended(landedAt: [trash.appending(path: "Bar.app")])
        moves.whenSettled(nil)
        moves.whenSettled {}
        #expect(moves.arrivals(["Bar.app"], known: [], in: trash, since: moves.look()) == ["Bar.app"])
    }
}
