import Darwin
@testable import PeelCore
import Testing

struct IgnoredSignalsTests {
    @Test func givesEachSignalItsHandlerBackOnceTheWorkEnds() {
        let ignored = IgnoredSignals([SIGUSR2])

        #expect(ignored.run { SignalDisposition.isIgnored(SIGUSR2) })
        #expect(!SignalDisposition.isIgnored(SIGUSR2))
    }
}
