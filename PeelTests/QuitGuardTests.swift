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
}
