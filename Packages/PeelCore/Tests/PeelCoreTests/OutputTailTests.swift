import Foundation
@testable import PeelCore
import Testing

struct OutputTailTests {
    @Test func keepsOnlyTheLastLines() {
        let output = Data((1...10).map { "line \($0)" }.joined(separator: "\n").utf8)

        #expect(OutputTail.lastLines(of: output, count: 3) == "line 8\nline 9\nline 10")
        #expect(OutputTail.lastLines(of: output, count: 20) == String(decoding: output, as: UTF8.self))
        #expect(OutputTail.lastLines(of: Data(), count: 3) == "")
    }

    /// The cost of a tail is the tail's, whatever came before, so a long upgrade stays as cheap to show as a short one.
    @Test func readsOnlyTheEndOfALongOutput() {
        let line = Data("==> Pouring a package\n".utf8)
        var output = Data()
        for _ in 0..<200_000 { output.append(line) }

        let clock = ContinuousClock()
        let took = clock.measure { _ = OutputTail.lastLines(of: output, count: 400) }
        #expect(took < .milliseconds(5), "\(took)")
    }
}
