import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct CommandsToRunTests {
    /// The question before the move can't be copied from, so its commands are on the page, and those still to run
    /// once the app is gone are in the alert after it, with Copy Details.
    @Test func anAppsCommandsAreOnItsPageAndThoseForAfterTheMoveReachTheAlert() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CommandsToRunTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        for file in ["usr/local/bin/battery", "private/etc/sudoers.d/battery"] {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }
        let environment = SearchEnvironment(homeDirectory: root.appending(path: "home"), rootDirectory: root)
        let cask = HomebrewPackage(name: "battery", kind: .cask, uninstallNeedsAnAdministrator: true)
        let first = try #require(CommandToRunFirst.of(cask, environment: environment))
        let left = try #require(LeftInTheSystem.of(cask, environment: environment))
        let app = InstalledApp(url: URL(filePath: "/Applications/battery.app"), bundleIdentifier: nil, name: "battery")

        let commands = CommandToRun.of(app, first: first, leftInTheSystem: left, cask: cask, naming: "battery")

        #expect(commands.map(\.command) == [first.command, left.command, "brew uninstall --cask battery"])
        #expect(commands.map(\.isForAfterwards) == [false, true, true])
        let outcome = RemovalOutcome()
        outcome.report(
            TrashResult(),
            commandsLeft: commands.filter(\.isForAfterwards).map { .init(app: $0.app, command: $0.command) }
        )
        #expect(!outcome.isEmpty)
        #expect(RemovalFailureAlert.message(for: outcome) == "battery: \(left.command)\n\nbattery: brew uninstall --cask battery")
        #expect(RemovalFailureAlert.offersDetails(for: outcome))
        #expect(RemovalFailureAlert.details(for: outcome).hasPrefix(String(localized: "Run these commands in Terminal to finish.")))
    }

    /// When the alert has something else to tell, its title says that, and the commands come under their own line.
    @Test func commandsLeftBesideAFailureComeUnderTheirOwnLine() {
        let outcome = RemovalOutcome()
        outcome.report(
            TrashResult(failures: [TrashFailure(url: URL(filePath: "/Applications/Example.app"), reason: .locked)]),
            commandsLeft: [.init(app: "Example", command: "sudo rm /etc/example")]
        )

        let paragraphs = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")

        #expect(paragraphs.suffix(2) == [String(localized: "Run this command in Terminal to finish."), "Example: sudo rm /etc/example"])
    }
}
