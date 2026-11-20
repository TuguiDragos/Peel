import FoundationModels
@testable import Peel
import PeelCore
import Testing

struct AppleIntelligenceAvailabilityTests {
    @Test func spaceSaysWhatAppleIntelligenceKeepsOnlyWhileItIsTurnedOn() {
        #expect(AppleIntelligence.isOn(.available))
        #expect(AppleIntelligence.isOn(.unavailable(.modelNotReady)))
        #expect(!AppleIntelligence.isOn(.unavailable(.appleIntelligenceNotEnabled)))
        #expect(!AppleIntelligence.isOn(.unavailable(.deviceNotEligible)))
    }
}
