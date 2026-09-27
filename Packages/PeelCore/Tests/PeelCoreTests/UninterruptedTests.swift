import Darwin
@testable import PeelCommandLine
import Testing

/// `peel` keeps running from a move, or a put back, until History records it.
struct UninterruptedTests {
    /// Whether `number` is ignored now, read without changing it.
    private static func isIgnored(_ number: Int32) -> Bool {
        var action = sigaction()
        guard sigaction(number, nil, &action) == 0 else { return false }
        return unsafeBitCast(action.__sigaction_u.__sa_handler, to: Int.self) == unsafeBitCast(SIG_IGN, to: Int.self)
    }

    /// Everything that would stop `peel` between a move and History is ignored meanwhile: Ctrl-C and a kill, and also
    /// a terminal closing or an SSH connection dropping, Ctrl-\, and output piped into a command that has quit.
    @Test func whatWouldStopPeelIsIgnoredUntilHistoryIsWritten() async {
        #expect(Set(Uninterrupted.signals) == [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGPIPE])
        let ignored = await Uninterrupted.run { Uninterrupted.signals.filter(Self.isIgnored) }
        #expect(ignored == Uninterrupted.signals)
    }

    /// A run that ends while another is still under way, as when tests run at once, leaves the other held: only the
    /// last one to end gives the signals their handlers back.
    @Test func aRunEndingFirstLeavesTheOtherHeld() async {
        let (entered, enter) = AsyncStream.makeStream(of: Void.self)
        let (released, release) = AsyncStream.makeStream(of: Void.self)
        let first = Task {
            await Uninterrupted.run {
                enter.yield()
                for await _ in released { break }
            }
        }
        for await _ in entered { break }

        await Uninterrupted.run {
            release.yield()
            await first.value
            #expect(Uninterrupted.signals.allSatisfy(Self.isIgnored), "the run still under way lost its hold")
        }
    }
}
