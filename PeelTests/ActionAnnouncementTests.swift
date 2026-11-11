import Accessibility
import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct ActionAnnouncementTests {
    private final class Spoken {
        var words: [AttributedString] = []
        var texts: [String] { words.map { String($0.characters) } }
    }

    private let example = InstalledApp(
        url: URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory),
        bundleIdentifier: "org.example.app",
        name: "Example"
    )

    @Test func aPrivacyResetFromAnAppsPageIsSpoken() async {
        let spoken = Spoken()
        let plan = RemovalPlan(app: example) { _ in [] }

        let reset = await plan.resetPrivacy(resetting: { _ in .reset }) { spoken.words.append($0) }
        let refused = await plan.resetPrivacy(resetting: { _ in .refused }) { spoken.words.append($0) }

        #expect(spoken.texts == [reset, refused].map { String(localized: $0.outcome(for: "Example")) })
    }

    @Test func aResetOfPermissionsAloneIsSpokenAfterWhatMoved() {
        let spoken = Spoken()
        let plan = ResetPlan(app: example) { spoken.words.append($0) }
        let reset = AppReset.Outcome(privacy: .reset)

        plan.tell(reset)
        plan.tell(AppReset.Outcome(stop: .appOpened))

        #expect(spoken.texts == [String(localized: ResetPlan.title(of: reset, app: "Example"))])
        #expect(spoken.words.first?.accessibilitySpeechAnnouncementPriority == .low)
    }

    @Test func aChangeOfTheHelperThatWentThroughTellsItsState() async {
        let spoken = Spoken()
        let helper = HelperModel(performing: { _ in }) { spoken.words.append($0) }

        let failure = await helper.uninstall()

        #expect(failure == nil)
        let state = String(localized: "\(String(localized: "Helper")): \(String(localized: helper.stateWords))")
        #expect(spoken.texts == (PrivilegedHelper.isAdministrator ? [state] : []))
    }

    @Test func aFailedChangeOfTheHelperIsLeftToItsAlert() async {
        struct Refused: Error {}
        let spoken = Spoken()
        let helper = HelperModel(performing: { _ in throw Refused() }) { spoken.words.append($0) }

        let failure = await helper.uninstall()

        #expect((failure != nil) == PrivilegedHelper.isAdministrator)
        #expect(spoken.words.isEmpty)
    }
}
