public import Foundation
internal import PeelPrivileged
import Synchronization

/// Peel's own moves to the Trash, so a watch on the Trash can tell them from the user's. `TrashService`, which
/// every removal goes through, says here when a move begins and where its items landed once it ends. Where they
/// landed is what counts: the Trash renames an item whose name is taken (`Foo 2.app` beside a `Foo.app` already
/// there), and a move that fails lands nothing.
public final class OwnTrashMoves: Sendable {
    public static let shared = OwnTrashMoves()

    private struct State {
        var underWay = 0
        /// How many moves have ended, which dates both a landing and the start of a look.
        var ended = 0
        /// Where each item landed, and which ended move landed it.
        var landed: [String: Int] = [:]
    }

    private let state = Mutex(State())
    private let settled = Mutex<(@Sendable () -> Void)?>(nil)

    public init() {}

    /// `action` runs whenever the last move under way ends, so the watch can look at the Trash again.
    public func whenSettled(_ action: @escaping @Sendable () -> Void) {
        settled.withLock { $0 = action }
    }

    func began() {
        state.withLock { $0.underWay += 1 }
    }

    func ended(landedAt urls: [URL]) {
        let isSettled = state.withLock { state in
            state.ended += 1
            for url in urls {
                state.landed[PathPattern.comparablePath(of: url)] = state.ended
            }
            state.underWay -= 1
            return state.underWay == 0
        }
        if isSettled {
            settled.withLock { $0 }?()
        }
    }

    /// Taken before the Trash is listed, and passed to `arrivals` with what the listing found.
    public func look() -> Int {
        state.withLock { $0.ended }
    }

    /// The names in `names`, the items now in `trash`, that are new since `known` and that Peel did not put
    /// there. Nil while a move of Peel's own is under way, since where it lands is not known yet: the listing
    /// does not count, and the end of the move says to look again.
    public func arrivals(_ names: Set<String>, known: Set<String>, in trash: URL, since look: Int) -> [String]? {
        state.withLock { state in
            guard state.underWay == 0 else { return nil }
            let folder = PathPattern.comparablePath(of: trash)
            let arrived = names.subtracting(known).sorted().filter { state.landed[folder + "/" + $0] == nil }
            // What landed in this Trash before the listing began has been seen by it, or has left since. Another
            // Trash keeps what landed there until it is listed itself.
            state.landed = state.landed.filter { $0.value > look || !PathComponents.isPath($0.key, inside: folder) }
            return arrived
        }
    }
}
