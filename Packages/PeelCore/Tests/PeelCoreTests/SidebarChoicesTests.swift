@testable import PeelCore
import Testing

struct SidebarChoicesTests {
    @Test func aToolNeverChosenFollowsItsDefault() {
        let choices = SidebarChoices(stored: "")

        #expect(choices.shows("plugins", byDefault: false) == false)
        #expect(choices.shows("space", byDefault: true) == true)
    }

    @Test func aChoiceWinsOverTheDefaultEitherWay() {
        var choices = SidebarChoices(stored: "")
        choices.choose("plugins", shows: true)
        choices.choose("space", shows: false)

        let kept = SidebarChoices(stored: choices.stored)

        #expect(kept.shows("plugins", byDefault: false) == true)
        #expect(kept.shows("space", byDefault: true) == false)
        #expect(kept.shows("homebrew", byDefault: false) == false)
        #expect(kept.shows("homebrew", byDefault: true) == true)
    }

    @Test func theOldListOfHiddenToolsCountsAsChosenOff() {
        let choices = SidebarChoices(hiddenBefore: "duplicates,cloud")

        #expect(choices.shows("duplicates", byDefault: true) == false)
        #expect(choices.shows("cloud", byDefault: true) == false)
        #expect(choices.shows("plugins", byDefault: false) == false)
        #expect(SidebarChoices(hiddenBefore: "") == SidebarChoices(stored: ""))
    }

    @Test func keepsANameThisVersionDoesNotKnowAndSkipsWhatMakesNoSense() {
        let choices = SidebarChoices(stored: "laterTool:1,space:0,broken,:1,plugins:yes")

        #expect(choices.shows("laterTool", byDefault: false) == true)
        #expect(choices.shows("space", byDefault: true) == false)
        #expect(choices.shows("plugins", byDefault: false) == false)
        #expect(SidebarChoices(stored: choices.stored) == choices)
    }
}
