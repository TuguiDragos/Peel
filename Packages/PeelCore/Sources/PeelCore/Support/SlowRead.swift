import Darwin
import Foundation
import Synchronization

/// Runs a read that may never return on a thread of its own, and stops waiting for it when the budget runs out,
/// the way `FileSize` walks a folder. Nil means no answer, never an empty folder.
enum SlowRead {
    /// The names in the folder at `url`: empty for anything that is not there or is not a folder, and nil when
    /// what it holds is not known: macOS refused to list it, the listing failed any other way, the read did not
    /// come back in time, or the task was canceled.
    static func names(in url: URL, within budget: TimeInterval = FileSize.budget) async -> [String]? {
        let path = url.path(percentEncoded: false)
        let listed: [String]?? = await answer(within: budget) { _ in
            do {
                return try FileManager.default.contentsOfDirectory(atPath: path)
            } catch {
                return holdsNothing(path) ? [] : nil
            }
        }
        return listed ?? nil
    }

    /// Whether `path` is not there or is not a folder, as `stat` tells. Foundation reports a link that leads back
    /// to itself as a missing file too, and that one is there.
    private static func holdsNothing(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return errno == ENOENT || errno == ENOTDIR }
        return info.st_mode & S_IFMT != S_IFDIR
    }

    /// Runs `read` on a thread of its own and returns its answer, or nil when it does not come within `budget`
    /// or the task is canceled. A read that works in steps can check `isGivenUp` and stop once nobody waits.
    static func answer<T: Sendable>(within budget: TimeInterval, _ read: @escaping @Sendable (_ isGivenUp: @escaping @Sendable () -> Bool) -> T) async -> T? {
        guard !Task.isCancelled else { return nil }
        let answer = Answer<T>()
        let thread = Thread { answer.give(read { answer.isGivenUp }) }
        thread.stackSize = 512 * 1_024
        thread.start()
        return await answer.wait(budget)
    }

    /// Its one waiter is woken once: by the answer, by the end of the budget, or by its own cancellation.
    private final class Answer<T: Sendable>: Sendable {
        private struct State {
            var value: T?
            var waiter: CheckedContinuation<Void, Never>?
            var isWoken = false
            /// True when the waiter was woken before the answer came. Whatever the read gives after that is
            /// dropped, since a read that stops when told returns only part of the answer.
            var isGivenUp = false
        }

        private let state = Mutex(State())

        var isGivenUp: Bool {
            state.withLock { $0.isGivenUp }
        }

        func give(_ value: T) {
            let waiter = state.withLock { state in
                state.value = value
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume()
        }

        func wait(_ budget: TimeInterval) async -> T? {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    let goesOnWaiting = state.withLock { state in
                        guard state.value == nil, !state.isWoken else { return false }
                        state.waiter = continuation
                        return true
                    }
                    guard goesOnWaiting else { return continuation.resume() }
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + budget) { self.wake() }
                }
            } onCancel: {
                wake()
            }
            return state.withLock { $0.isGivenUp ? nil : $0.value }
        }

        private func wake() {
            let waiter = state.withLock { state in
                state.isWoken = true
                if state.value == nil { state.isGivenUp = true }
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume()
        }
    }
}
