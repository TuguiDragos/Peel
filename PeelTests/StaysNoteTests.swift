import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct StaysNoteTests {
    @Test func aRowThePersonSelectedNeverSaysItIsNotSelected() {
        #expect(Leftover.staysNote(with: "Example", isSelected: false).hasPrefix("Not selected"))
        let selected = Leftover.staysNote(with: "Example", isSelected: true)
        #expect(!selected.hasPrefix("Not selected"))
        #expect(selected.contains("Example"))
    }
}
