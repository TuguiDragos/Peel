import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct TeamChangeTests {
    /// A team identifier alone says nothing to most people, so the note says it is a team, who signs the app now when
    /// Peel knows, what the change can mean, and what to do.
    @Test func aSignerChangeSaysWhatItCanMeanAndWhatToDo() {
        let changed = TeamRegistry.Change(
            bundleIdentifier: "org.example.app", previous: "ABCDE12345", current: "VWXYZ67890"
        )
        let unsigned = TeamRegistry.Change(bundleIdentifier: "org.example.app", previous: "ABCDE12345", current: "")

        let named = changed.explanation(named: "Example Inc")

        #expect(named.contains("team ABCDE12345"))
        #expect(named.contains("Example Inc, team VWXYZ67890"))
        #expect(changed.explanation(named: nil).contains("team VWXYZ67890"))
        for words in [named, changed.explanation(named: nil), unsigned.explanation(named: "Example Inc")] {
            #expect(words.contains("get the app again from its maker"), "\(words)")
        }
    }
}
