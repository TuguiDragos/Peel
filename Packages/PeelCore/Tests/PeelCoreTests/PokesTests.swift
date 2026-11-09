import Foundation
@testable import PeelCore
import Testing

struct PokesTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func wakesOnTheFifthClickInARowAndStartsCountingAgain() {
        var pokes = Pokes()
        let answers = (0..<6).map { pokes.poke(at: start.addingTimeInterval(Double($0) * 0.4)) }

        #expect(answers == [.squash(count: 1), .squash(count: 2), .squash(count: 3), .squash(count: 4), .wake,
                           .squash(count: 1)])
    }

    @Test func aPauseBetweenTwoClicksStartsTheCountAgain() {
        var pokes = Pokes()
        for second in 0..<4 {
            #expect(pokes.poke(at: start.addingTimeInterval(Double(second))) == .squash(count: second + 1))
        }

        #expect(pokes.poke(at: start.addingTimeInterval(3 + Pokes.pause + 0.1)) == .squash(count: 1))
        for second in 1..<4 {
            let answer = pokes.poke(at: start.addingTimeInterval(3 + Pokes.pause + 0.1 + Double(second)))
            #expect(answer == .squash(count: second + 1))
        }
        #expect(pokes.poke(at: start.addingTimeInterval(3 + Pokes.pause + 0.1 + 4)) == .wake)
    }
}
