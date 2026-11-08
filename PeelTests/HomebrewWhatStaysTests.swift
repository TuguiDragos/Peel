import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HomebrewWhatStaysTests {
    @Test func aCaskUninstalledInTerminalSaysBesideItsCommandWhatItsAppLeaves() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "HomebrewWhatStaysTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        for file in ["usr/local/bin/battery", "private/etc/sudoers.d/battery", "private/etc/paths.d/postgresapp"] {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }
        let environment = SearchEnvironment(homeDirectory: root.appending(path: "home"), rootDirectory: root)
        let battery = HomebrewPackage(name: "battery", kind: .cask, uninstallNeedsAnAdministrator: true)
        let postgres = HomebrewPackage(name: "postgres-app", kind: .cask)
        let said = { (package: HomebrewPackage) in
            HomebrewDetailView.besideTheCommand(
                package,
                commandToRunFirst: CommandToRunFirst.of(package, environment: environment),
                leftInTheSystem: LeftInTheSystem.of(package, environment: environment)
            )
        }

        let first = try #require(CommandToRunFirst.of(battery, environment: environment))
        let left = try #require(LeftInTheSystem.of(battery, environment: environment))
        #expect(said(battery) == .init(name: "battery", commandToRunFirst: first, leftInTheSystem: left))
        #expect(said(postgres) == nil, "a cask Peel uninstalls says it in its question")
    }
}
