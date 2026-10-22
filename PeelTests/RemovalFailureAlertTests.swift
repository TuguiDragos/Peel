import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct RemovalFailureAlertTests {
    @Test func listsTheFirstAppsThatStayedAndCountsTheOthers() {
        let apps = (1...30).map { index in
            InstalledApp(
                url: URL(filePath: "/Applications/Example \(index).app"),
                bundleIdentifier: "org.example.app\(index)", name: "Example \(index)"
            )
        }
        let outcome = RemovalOutcome()
        outcome.report(
            TrashResult(failures: apps.map { TrashFailure(url: $0.url, reason: .locked) }),
            privacy: apps.map { ($0, .reset) },
            keptTheirFiles: apps.map(\.name)
        )
        let most = RemovalFailureAlert.mostListed
        let paragraphs = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        #expect(paragraphs.count == 3 * (most + 1), "\(paragraphs.count)")
        #expect(paragraphs.filter { $0.contains("Example 30") }.isEmpty)
        let details = RemovalFailureAlert.details(for: outcome).components(separatedBy: "\n\n")
        #expect(details.filter { $0.contains("Example 30") }.count == 3)
    }

    @Test func copiesTheShellLineTheAlertShows() {
        let outcome = RemovalOutcome()
        outcome.report(
            TrashResult(failures: [TrashFailure(url: URL(filePath: "/Applications/Example.app"), reason: .locked)]),
            shellReferences: [ShellReferences.Reference(file: URL(filePath: "/Users/someone/.zshrc"), line: 12)]
        )
        let shown = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        let line = shown.first { $0.contains("/Users/someone/.zshrc") }
        #expect(line != nil)
        #expect(RemovalFailureAlert.details(for: outcome).components(separatedBy: "\n\n").contains(line ?? ""))
    }

    @Test func offersTheDetailsWhereTheAlertNamesOnlyTheFirstApps() {
        let apps = (1...6).map { index in
            InstalledApp(
                url: URL(filePath: "/Applications/Example \(index).app"),
                bundleIdentifier: "org.example.app\(index)", name: "Example \(index)"
            )
        }
        let many = RemovalOutcome()
        many.report(TrashResult(), privacy: apps.map { ($0, .notKnownToTheSystem) })
        #expect(RemovalFailureAlert.offersDetails(for: many))
        let few = RemovalOutcome()
        few.report(TrashResult(), privacy: apps.prefix(2).map { ($0, .notKnownToTheSystem) })
        #expect(!RemovalFailureAlert.offersDetails(for: few))
    }

    @Test func namesTheFirstAppsToQuitAndShellLinesAndCountsTheOthers() {
        let outcome = RemovalOutcome()
        outcome.report(
            TrashResult(),
            appsToQuit: (1...6).map { "Example \($0)" },
            shellReferences: (1...6).map {
                ShellReferences.Reference(file: URL(filePath: "/Users/someone/.zshrc"), line: $0 * 10)
            }
        )
        let paragraphs = RemovalFailureAlert.message(for: outcome).components(separatedBy: "\n\n")
        #expect(paragraphs.filter { $0.contains("Example") }.count == RemovalFailureAlert.mostListed)
        let shell = paragraphs.first { $0.contains(".zshrc") } ?? ""
        #expect(shell.contains("40") && !shell.contains("50") && !shell.contains("60"), "\(shell)")
        let details = RemovalFailureAlert.details(for: outcome)
        #expect(details.contains("Example 6") && details.contains("60"))
        #expect(RemovalFailureAlert.offersDetails(for: outcome))
    }
}
