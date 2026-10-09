import Foundation
@testable import PeelCore
import Testing

@Suite(.serialized)
struct StoredSwitchTests {
    private let key = "org.example.peel.storedSwitch"

    private func reading(_ stored: Any?, whenNeverSet: Bool) -> Bool {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        var domain = arguments
        domain[key] = stored
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        return defaults.isOn(key, whenNeverSet: whenNeverSet)
    }

    @Test func aSwitchGivenAsTextReadsAsTheSwitchShowsIt() {
        #expect(!reading("NO", whenNeverSet: true))
        #expect(reading("YES", whenNeverSet: false))
        #expect(!reading("0", whenNeverSet: true))
        #expect(!reading(false, whenNeverSet: true))
        #expect(reading(true, whenNeverSet: false))
    }

    @Test func aSwitchNeverSetReadsAsItsDefault() {
        #expect(reading(nil, whenNeverSet: true))
        #expect(!reading(nil, whenNeverSet: false))
    }
}
