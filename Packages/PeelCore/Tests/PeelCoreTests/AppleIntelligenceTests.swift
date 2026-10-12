import Foundation
@testable import PeelCore
import Testing

struct AppleIntelligenceTests {
    @Test func figuresWhatAppleSaysForEachMac() {
        let gibibyte: Int64 = 1_073_741_824
        #expect(AppleIntelligence.storage(chip: "Apple M1", memory: 8 * gibibyte) == 8_000_000_000)
        #expect(AppleIntelligence.storage(chip: "Apple M2 Pro", memory: 32 * gibibyte) == 8_000_000_000)
        #expect(AppleIntelligence.storage(chip: "Apple M3", memory: 8 * gibibyte) == 8_000_000_000)
        #expect(AppleIntelligence.storage(chip: "Apple M3", memory: 16 * gibibyte) == 14_000_000_000)
        #expect(AppleIntelligence.storage(chip: "Apple M4 Max", memory: 12 * gibibyte) == 14_000_000_000)
        #expect(AppleIntelligence.storage(chip: "Apple M10", memory: 24 * gibibyte) == 14_000_000_000)
        #expect(AppleIntelligence.storage(chip: "Intel(R) Core(TM) i7-8850H CPU @ 2.60GHz", memory: 16 * gibibyte) == nil)
        #expect(AppleIntelligence.storage(chip: "Apple Mystery", memory: 16 * gibibyte) == nil)
        #expect(AppleIntelligence.storage(chip: "", memory: 16 * gibibyte) == nil)
    }
}
