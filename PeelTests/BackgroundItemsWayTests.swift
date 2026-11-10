import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct BackgroundItemsWayTests {
    /// The System group starts hidden, so the reason says where Background Items is and the alert opens it.
    @Test func aJobHoldingAnItemLeadsToBackgroundItems() {
        let held = RemovalOutcome()
        held.report(TrashResult(failures: [
            TrashFailure(url: URL(filePath: "/Users/someone/Library/Example"), reason: .heldOpenByAJob(by: ["Example"])),
        ]))
        let locked = RemovalOutcome()
        locked.report(TrashResult(failures: [TrashFailure(url: URL(filePath: "/Users/someone/Example"), reason: .locked)]))
        let names = ["Example"].formatted(.list(type: .and))

        #expect(RemovalFailureAlert.needsBackgroundItems(held))
        #expect(!RemovalFailureAlert.needsBackgroundItems(locked))
        #expect(TrashFailure.Reason.heldOpenByAJob(by: ["Example"]).explanation(in: nil) == String(localized: "It is in use by \(names). Quit \(names), or stop it in Background Items (View > Background Items) if it has no window, then try again."))
    }
}
