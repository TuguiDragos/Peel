import Foundation
@testable import Peel
import PeelCore
import Testing

struct BackgroundItemTextTests {
    @Test func aJobPeelLeavesAloneSaysWhyInItsCircledI() {
        #expect(BackgroundItemDetailView.doesNotChangeIt.key == "Peel does not change this job")
        #expect(BackgroundItemDetailView.whyItsNameIsUnusable(.holdsASlash).key == "launchctl reads its name only up to a slash, so a command for it could reach another job.")
        #expect(BackgroundItemDetailView.whyItsNameIsUnusable(.notTakenByTheHelper).key == "Its name has characters the Peel helper never passes to launchctl.")
        #expect(BackgroundItemDetailView.whyItsNameIsUnusable(.holdsAControlCharacter).key == "Its name has a control character, which Peel never passes to launchctl.")
        #expect(BackgroundItemDetailView.anotherFileNote.key == "macOS runs this job from another file with the same name, so this file is not loaded.")
        #expect(BackgroundItemDetailView.systemExtensionNote.key == "Only System Settings > General > Login Items & Extensions changes it.")
    }

    @Test func aJobWithAnAppleNameMacOSDidNotInstallSaysSo() {
        #expect(BackgroundItemDetailView.notInstalledByMacOS.key == "Not installed by macOS")
        #expect(BackgroundItemDetailView.appleNameNote.key == "Its name says Apple, but macOS did not install it. Look at the file to see what put it there.")
        #expect(BackgroundItemDetailView.macOSJobNameNote.key == "macOS runs a job by this name, but it did not install this file. Look at the file to see what put it there.")
    }

    @Test func whyTheStateIsNotKnownIsShort() {
        let lists = "Peel could not read from launchctl which jobs are loaded or turned off."
        #expect(BackgroundItemDetailView.whyStateIsNotKnown(.jobsNotListed).key == lists)
        #expect(BackgroundItemDetailView.whyStateIsNotKnown(.disabledNotListed).key == lists)
        #expect(BackgroundItemDetailView.whyStateIsNotKnown(.whichFileNotSaid).key == "Another file declares the same job, and macOS did not say which one it loaded.")
        #expect(BackgroundItemDetailView.whyStateIsNotKnown(nil).key == "Peel could not read what macOS answered about this job.")
    }
}
