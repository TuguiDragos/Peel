import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct BackgroundItemTrashWordsTests {
    private func job(_ source: BackgroundItem.Source) -> BackgroundItem {
        BackgroundItem(
            label: "org.example.agent", kind: .agent, source: source, plistURL: URL(filePath: "/x/org.example.agent.plist"),
            program: "/usr/local/bin/agent", runsAtLoad: true, keepsAlive: false, ownerBundleIdentifier: nil,
            ownerName: nil, ownerURL: nil, isOrphan: false, state: .loaded, isDisabled: false
        )
    }

    @Test func saysWhatAMoveDoesForEveryAccountThatRunsTheAgent() {
        #expect(job(.systemLibrary).whenTrashed.map { String(localized: $0) } == String(localized: "Peel stops the job for your account once its file is in the Trash. Other accounts logged in now run it until they log out, and none starts it again."))
        #expect(job(.userLibrary).whenTrashed.map { String(localized: $0) } == String(localized: "Peel stops the job once its file is in the Trash."))
    }

    @Test func saysWhenAJobStillRunningEnds() {
        var agent = job(.userLibrary)
        agent.state = .unknown
        var daemon = BackgroundItem(
            label: "org.example.daemon", kind: .daemon, source: .systemLibrary,
            plistURL: URL(filePath: "/x/org.example.daemon.plist"), program: "/usr/local/bin/daemon", runsAtLoad: true,
            keepsAlive: false, ownerBundleIdentifier: nil, ownerName: nil, ownerURL: nil, isOrphan: false,
            state: .unknown, isDisabled: false
        )
        daemon.isNamedByItsFile = true
        agent.isNamedByItsFile = true
        var inTheBackground = agent
        inTheBackground.loadsInTheBackgroundSession = true
        let atLogout = String(localized: "macOS won’t start it again: it stops for good when you log out.")
        let atRestart = String(localized: "macOS won’t start it again: it stops for good when the Mac restarts.")

        #expect(agent.whenTrashed.map { String(localized: $0) } == atLogout)
        #expect(daemon.whenTrashed.map { String(localized: $0) } == atRestart)
        #expect(inTheBackground.whenTrashed.map { String(localized: $0) } == atRestart)
    }

    @Test func promisesNothingForAFileLaunchdDoesNotHaveLoaded() {
        var copy = job(.userLibrary)
        copy.anotherFileIsLoaded = true
        var notLoaded = job(.userLibrary)
        notLoaded.state = .notLoaded

        #expect(copy.whenTrashed == nil)
        #expect(notLoaded.whenTrashed == nil)
    }

    @Test func promisesNoStopForARowNamedByItsFile() {
        var named = job(.userLibrary)
        named.state = .unknown
        named.isClosedToPeel = true
        named.isNamedByItsFile = true

        #expect(named.whenTrashed.map { String(localized: $0) } == String(localized: "macOS won’t start it again: it stops for good when you log out."))
    }
}
