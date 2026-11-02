import SwiftUI
@testable import Peel
import Testing

struct MotionTests {
    @Test func aNumberFadesToItsNewValueUnderReduceMotion() {
        #expect(NumberTransition.transition(to: 12, reducingMotion: true) == .opacity)
        #expect(NumberTransition.transition(to: 12, reducingMotion: false) == .numericText(value: 12))
    }
}
