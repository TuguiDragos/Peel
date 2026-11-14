import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct OrphanOwnersNoteTests {
    @Test func thePageSaysWhenTheListOfOwnersCannotBeRead() {
        #expect(OrphanList.saysOwnersCannotBeRead(owners: nil))
        #expect(!OrphanList.saysOwnersCannotBeRead(owners: [:]))
        #expect(!OrphanList.saysOwnersCannotBeRead(owners: ["org.example.given": .app("org.example.app")]))
    }
}
