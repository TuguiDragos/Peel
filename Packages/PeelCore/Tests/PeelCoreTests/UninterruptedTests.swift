import Darwin
@testable import PeelCommandLine
import Testing

/// `peel` keeps running from a move, or a put back, until History records it.
struct UninterruptedTests {
    /// Everything that would stop `peel` between a move and History is ignored meanwhile: Ctrl-C and a kill, and also
    /// a terminal closing or an SSH connection dropping, Ctrl-\, and output piped into a command that has quit.
    @Test func whatWouldStopPeelIsIgnoredUntilHistoryIsWritten() async {
        #expect(Set(Uninterrupted.signals) == [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGPIPE])
        let ignored = await Uninterrupted.run { Uninterrupted.signals.filter(SignalDisposition.isIgnored) }
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
            #expect(Uninterrupted.signals.allSatisfy(SignalDisposition.isIgnored), "the run still under way lost its hold")
        }
    }
}
