import AppKit
@testable import Peel
import Testing

struct QuitGuardTests {
    @Test func letsAQuitGoAheadWhileNothingIsUnderWay() {
        #expect(QuitGuard().replyToQuit() == .terminateNow)
    }

    @Test func refusesAQuitWhilePeelRemovesItself() async {
        let guardian = QuitGuard()
        var reply: NSApplication.TerminateReply?

        await guardian.runRefusingQuit { reply = guardian.replyToQuit() }

        #expect(reply == .terminateCancel)
        #expect(guardian.replyToQuit() == .terminateNow)
    }

    @Test func aRefusalOutranksWorkAQuitWouldWaitFor() async {
        let guardian = QuitGuard()
        var reply: NSApplication.TerminateReply?

        await guardian.runRefusingQuit {
            await guardian.run { reply = guardian.replyToQuit() }
        }

        #expect(reply == .terminateCancel)
    }

    @Test func aQuitDuringStoppableWorkStopsItOnlyOnThePersonsWord() async {
        final class Record {
            var asked = 0
            var stopped = 0
            var answers: [Bool] = []
        }
        let record = Record()
        var reply: NSApplication.TerminateReply?

        let keepingOpen = QuitGuard(
            asksToStop: { record.asked += 1; return false }, answer: { record.answers.append($0) }
        )
        await keepingOpen.run(stoppingWith: { record.stopped += 1 }) { reply = keepingOpen.replyToQuit() }
        #expect(reply == .terminateCancel)
        #expect(record.asked == 1 && record.stopped == 0 && record.answers.isEmpty)

        let stopping = QuitGuard(asksToStop: { true }, answer: { record.answers.append($0) })
        await stopping.run(stoppingWith: { record.stopped += 1 }) { reply = stopping.replyToQuit() }
        #expect(reply == .terminateLater)
        #expect(record.stopped == 1 && record.answers == [true])
    }
}
