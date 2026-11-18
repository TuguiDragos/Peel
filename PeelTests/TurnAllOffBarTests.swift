import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct TurnAllOffBarTests {
    private func height(hasSomethingOn: Bool) -> CGFloat {
        let bar = TurnAllOffBar(explanation: "Turning one off takes it out of that file.", hasSomethingOn: hasSomethingOn) {}
        let host = NSHostingView(rootView: VStack(spacing: 0) { bar }.frame(width: 600))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test func showsNoBarWhileNothingIsOn() {
        #expect(height(hasSomethingOn: false) == 0)
        #expect(height(hasSomethingOn: true) > 0)
    }
}
