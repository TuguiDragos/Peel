import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct UpdatePanelTests {
    @Test func saysNoNotesCameOnlyBesideALinkThatLeadsElsewhere() throws {
        let page = try #require(URL(string: "https://example.com/notes"))
        let notes = ReleaseNotesLink(url: page, title: "Release Notes", leadsToTheNotes: true)
        let site = ReleaseNotesLink(url: page, title: "Website", leadsToTheNotes: false)
        func said(_ standing: ReleaseNotesMemory.Standing, beside link: ReleaseNotesLink?) -> String? {
            standing.sentence(beside: link).map { String(localized: $0) }
        }

        #expect(said(.notGiven, beside: notes) == nil)
        #expect(said(.notGiven, beside: site) == "This update came with no notes.")
        #expect(said(.notGiven, beside: nil) == nil)
        #expect(said(.unanswered, beside: notes) == "Peel couldn’t get this update’s notes. It asks again later.")
        #expect(said(.notAskedYet, beside: notes) == nil)
    }
}
