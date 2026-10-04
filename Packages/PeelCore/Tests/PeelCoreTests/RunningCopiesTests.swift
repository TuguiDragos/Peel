import Foundation
@testable import PeelCore
import Testing

struct RunningCopiesTests {
    private let chrome = InstalledApp(
        url: URL(filePath: "/Applications/Google Chrome.app", directoryHint: .isDirectory),
        bundleIdentifier: "com.google.Chrome",
        name: "Google Chrome",
        embeddedBundleIdentifiers: ["com.google.Keystone.Agent"]
    )
    private let canary = InstalledApp(
        url: URL(filePath: "/Applications/Google Chrome Canary.app", directoryHint: .isDirectory),
        bundleIdentifier: "com.google.Chrome.canary",
        name: "Google Chrome Canary"
    )

    private func process(_ identifier: String, at path: String?, pid: pid_t = 1) -> RunningCopies.Process {
        RunningCopies.Process(identifier: pid, bundleIdentifier: identifier, bundleURL: path.map { URL(filePath: $0) })
    }

    private func belonging(_ running: [RunningCopies.Process]) -> [String] {
        RunningCopies.belonging(to: chrome, among: running, installedApps: [chrome, canary]).map(\.bundleIdentifier)
    }

    /// What runs from inside the app counts whatever its name begins with. A slash and a combining mark after it
    /// are one `Character`, so to a comparison of characters a helper named that way ran from nowhere, and the
    /// app's files could move while it ran.
    @Test func whatRunsFromInsideTheAppCountsWhateverItsNameBeginsWith() {
        #expect(belonging([process("org.example.unrelated", at: "/Applications/Google Chrome.app/\u{301}Helper.app")]) == ["org.example.unrelated"])
    }

    /// The app, what runs from inside it, what it embeds, and what continues its identifier all count, so
    /// nothing rewrites the app's files while they move.
    @Test func takesTheAppAndWhatItShips() {
        #expect(belonging([
            process("com.google.Chrome", at: "/Applications/Google Chrome.app"),
            process("com.google.Chrome.helper", at: "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app"),
            process("com.google.Keystone.Agent", at: "/Library/Google/GoogleSoftwareUpdate/Agent.app"),
            process("com.google.Chrome.framework.AlertNotificationService", at: nil),
        ]) == ["com.google.Chrome", "com.google.Chrome.helper", "com.google.Keystone.Agent", "com.google.Chrome.framework.AlertNotificationService"])
    }

    /// Chrome Canary continues Chrome's identifier and is another installed app, not a helper of Chrome's.
    @Test func leavesAnotherInstalledAppWhoseNameContinuesThisOne() {
        #expect(belonging([
            process("com.google.Chrome.canary", at: "/Applications/Google Chrome Canary.app"),
            process("com.google.Chrome.canary.helper", at: "/Applications/Google Chrome Canary.app/Contents/Frameworks/Helper.app"),
        ]).isEmpty)
    }

    /// The app with the longer identifier wins: Canary's helper also continues Chrome's identifier, but is Canary's.
    @Test func givesAHelperToTheAppWithTheLongerName() {
        let helper = process("com.google.Chrome.canary.helper", at: nil)

        #expect(RunningCopies.belonging(to: canary, among: [helper], installedApps: [chrome, canary]) == [helper])
        #expect(RunningCopies.belonging(to: chrome, among: [helper], installedApps: [chrome, canary]).isEmpty)
    }

    /// An identifier the bundle embeds can also be an installed app of its own, and then that app owns the process.
    @Test func leavesAnEmbeddedNameThatIsAnotherInstalledApp() {
        let agent = InstalledApp(url: URL(filePath: "/Applications/Keystone.app", directoryHint: .isDirectory), bundleIdentifier: "com.google.Keystone.Agent", name: "Keystone")
        let running = [process("com.google.Keystone.Agent", at: "/Applications/Keystone.app")]

        #expect(RunningCopies.belonging(to: chrome, among: running, installedApps: [chrome, agent]).isEmpty)
    }

    /// A process running from `/Applications` does not belong to an old copy in Downloads: quitting it would
    /// close the copy in use.
    @Test func leavesACopyOfTheAppRunningFromSomewhereElse() {
        let old = InstalledApp(url: URL(filePath: "/Users/x/Downloads/Google Chrome.app", directoryHint: .isDirectory), bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        let running = [process("com.google.Chrome", at: "/Applications/Google Chrome.app/")]

        #expect(RunningCopies.belonging(to: old, among: running, installedApps: [chrome, old]).isEmpty)
        #expect(RunningCopies.belonging(to: chrome, among: running, installedApps: [chrome, old]).count == 1)
        // A reset clears settings both copies write, so for a reset the other copy counts.
        #expect(
            RunningCopies.belonging(to: old, among: running, installedApps: [chrome, old], sharingItsSettings: true)
                .count == 1
        )
    }

    /// An app that continues the identifier and runs from somewhere Peel does not list apps, such as Chrome Canary
    /// on another disk, is an app of its own. What runs from inside a Library, as an agent does, is the app's.
    @Test func leavesAnAppOfItsOwnThatContinuesTheIdentifierWhereverItRuns() {
        let running = [
            process("com.google.Chrome.canary", at: "/Volumes/Disk/Google Chrome Canary.app"),
            process("com.google.Chrome.agent", at: "/Users/x/Library/Application Support/Google/Agent.app"),
        ]

        let mac = SearchEnvironment(
            homeDirectory: URL(filePath: "/Users/x", directoryHint: .isDirectory),
            rootDirectory: URL(filePath: "/", directoryHint: .isDirectory)
        )

        let belonging = RunningCopies.belonging(to: chrome, among: running, installedApps: [chrome], environment: mac)

        #expect(belonging.map(\.bundleIdentifier) == ["com.google.Chrome.agent"])
    }

    /// Bundle identifiers are case insensitive, so a process written in other capitals is still the app's.
    @Test func readsIdentifiersWithoutCase() {
        let chromeInCapitals = process("COM.GOOGLE.CHROME", at: "/Applications/Google Chrome.app")
        #expect(belonging([chromeInCapitals]) == ["COM.GOOGLE.CHROME"])
        #expect(belonging([process("com.google.chrome.helper", at: nil)]) == ["com.google.chrome.helper"])
        #expect(belonging([process("com.google.keystone.agent", at: nil)]) == ["com.google.keystone.agent"])
        #expect(belonging([process("COM.GOOGLE.CHROME.CANARY", at: nil)]).isEmpty)
    }

    /// If it is not known where a process runs from, a matching identifier counts it as the app, to be safe.
    @Test func countsTheAppWhenWhereItRunsFromIsNotKnown() {
        #expect(belonging([process("com.google.Chrome", at: nil)]) == ["com.google.Chrome"])
    }
}
