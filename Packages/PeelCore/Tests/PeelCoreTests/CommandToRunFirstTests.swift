import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

@Suite struct CommandToRunFirstTests {
    @Test func namesBatterysUninstallOnlyWhileItsToolIsThere() throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let battery = InstalledApp(
            url: directory.url.appending(path: "root/Applications/battery.app"),
            bundleIdentifier: "co.palokaj.battery",
            name: "battery"
        )
        #expect(CommandToRunFirst.of(battery, environment: environment) == nil)

        try directory.file("root/usr/local/bin/battery")

        #expect(
            CommandToRunFirst.of(battery, environment: environment)
                == CommandToRunFirst(command: "battery uninstall", undoes: .chargingLimit)
        )
        #expect(
            CommandToRunFirst.of(HomebrewPackage(name: "battery", kind: .cask), environment: environment)?.command
                == "battery uninstall"
        )
        #expect(CommandToRunFirst.of(HomebrewPackage(name: "battery", kind: .formula), environment: environment) == nil)
        let other = InstalledApp(
            url: directory.url.appending(path: "root/Applications/Example.app"),
            bundleIdentifier: "org.example.battery",
            name: "Example"
        )
        #expect(CommandToRunFirst.of(other, environment: environment) == nil)
    }

    @Test func anUninstallOfBatterySaysToRunItsUninstallFirst() async throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        try directory.file("root/usr/local/bin/battery")
        let battery = InstalledApp(
            url: try directory.directory("root/Applications/battery.app"),
            bundleIdentifier: "co.palokaj.battery",
            name: "battery"
        )

        let plan = await Uninstallation.prepare(battery, installedApps: [battery], environment: environment)

        #expect(plan.commandToRunFirst?.command == "battery uninstall")
        #expect(UninstallCommand.warnings(
            moving: [battery.url], of: battery, uninstallsItself: nil, leftInTheSystem: nil,
            commandToRunFirst: plan.commandToRunFirst, resettingPrivacy: false
        ) == [
            "battery may have paused this Mac's charging at a limit. Before it goes, run `battery uninstall`, which turns charging back on and removes its tools from /usr/local/bin.",
        ])
    }
}
