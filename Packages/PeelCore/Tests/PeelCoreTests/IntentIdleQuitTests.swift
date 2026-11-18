import CoreServices
import Foundation
@testable import PeelCore
import Testing

struct IntentIdleQuitTests {
    private func appleEvent(_ eventID: AEEventID, withAReason: Bool = false) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass), eventID: eventID, targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        if withAReason {
            event.setParam(NSAppleEventDescriptor(enumCode: OSType(kAELogOut)), forKeyword: AEKeyword(kAEQuitReason))
        }
        return event
    }

    /// Stands in for linkd, which a test can't be: the process 4242 runs linkd.
    private let linkd: (pid_t) -> String? = { $0 == 4242 ? "/usr/libexec/linkd" : nil }

    @Test func knowsTheQuitLinkdSendsOnceAnIntentHasEnded() {
        #expect(IntentIdleQuit.isLinkdsQuit(appleEvent(kAEQuitApplication), sentBy: 4242, programOf: linkd))
    }

    @Test func leavesEveryOtherQuitAlone() {
        let withAReason = appleEvent(kAEQuitApplication, withAReason: true)

        #expect(!IntentIdleQuit.isLinkdsQuit(withAReason, sentBy: 4242, programOf: linkd))
        #expect(!IntentIdleQuit.isLinkdsQuit(appleEvent(kAEQuitApplication), sentBy: getpid()))
        #expect(!IntentIdleQuit.isLinkdsQuit(appleEvent(kAEQuitApplication), sentBy: nil, programOf: linkd))
        #expect(!IntentIdleQuit.isLinkdsQuit(appleEvent(kAEOpenApplication), sentBy: 4242, programOf: linkd))
        #expect(!IntentIdleQuit.isAsked(by: appleEvent(kAEQuitApplication)))
        #expect(!IntentIdleQuit.isAsked(by: nil))
    }
}
