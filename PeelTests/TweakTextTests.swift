import Foundation
@testable import Peel
import PeelCore
import Testing

struct TweakTextTests {
    @Test func theBarSaysHowManySettingsPeelChanged() {
        #expect(TweakPage.explanation(changed: 3).key == "Peel changed ^[%lld setting](inflect: true).")
    }

    @Test func theCircledINotesAreShort() {
        #expect(TweakState.Elsewhere.thisMac.why.key == "This Mac has its own value for this setting, which macOS reads first. Peel does not change it.")
        #expect(TweakState.Elsewhere.everyAccount.why.key == "An administrator set this for every account on this Mac. Peel leaves it as it is.")
        #expect(TweakState.Elsewhere.everyApp.why.key == "macOS sets this for every app at once, so a switch for one app would change nothing.")
        #expect(Tweak.Restart.relaunchApps.sentence?.key == "Apps already open keep the old setting until you reopen them.")
        #expect(TweakRow.followsMacOSsControl.key == "Changes made to it in macOS show here too.")
        #expect(TweakRow.leftToMacOS.key == "Screenshots now go to the Desktop")
        #expect(TweakRow.leftToMacOSNote.key == "The folder you chose before can no longer take them, so macOS saves them on the Desktop.")
        #expect(SleepNotice.whyItCannotSleep.key == "Something turned sleep off, even with the lid closed. It stays after a restart, and System Settings does not show it.")
    }

    @Test func appleIntelligenceRowsShowThePathAndKeepTheRestInTheirNote() {
        #expect(AppleIntelligenceSwitch.siri.words.place.key == "System Settings > Siri > Turn Off Siri")
        #expect(AppleIntelligenceSwitch.siri.words.note?.key == "To keep Siri without Siri AI, turn Siri on again and select Use Siri Classic.")
        #expect(AppleIntelligenceSwitch.screenTime.words.place.key == "System Settings > Screen Time > Content & Privacy > Siri")
        #expect(AppleIntelligenceSwitch.screenTime.words.note?.key == "Turn off Siri AI there, or block capabilities such as Writing Assistance.")
        #expect(AppleIntelligenceSwitch.notificationSummaries.words.note == nil)
    }
}
