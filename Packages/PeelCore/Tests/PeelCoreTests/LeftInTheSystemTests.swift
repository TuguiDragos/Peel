import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

@Suite struct LeftInTheSystemTests {
    private struct Mac: ~Copyable {
        let directory: TemporaryDirectory
        let environment: SearchEnvironment

        init() throws {
            directory = try TemporaryDirectory()
            environment = SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
        }

        func left(_ identifier: String) -> LeftInTheSystem? {
            let app = InstalledApp(
                url: directory.url.appending(path: "root/Applications/Example.app"),
                bundleIdentifier: identifier,
                name: "Example"
            )
            return LeftInTheSystem.of(app, environment: environment)
        }

        func left(cask token: String, kind: HomebrewPackage.Kind = .cask) -> LeftInTheSystem? {
            LeftInTheSystem.of(HomebrewPackage(name: token, kind: kind), environment: environment)
        }
    }

    @Test func namesBatterysRuleForSudoOnlyWhileItIsThere() throws {
        let mac = try Mac()
        #expect(mac.left("co.palokaj.battery") == nil)

        try mac.directory.file("root/private/etc/sudoers.d/battery")
        let found = mac.left("co.palokaj.battery")
        let left = try #require(found)

        #expect(left.paths == ["/etc/sudoers.d/battery"])
        #expect(left.ruleForSudo == "/etc/sudoers.d/battery")
        #expect(left.command == "sudo rm /etc/sudoers.d/battery")
    }

    @Test func removesRancherDesktopsFolderAndItsRuleInOneCommand() throws {
        let mac = try Mac()
        try mac.directory.file("root/private/etc/sudoers.d/zzzzz-rancher-desktop-lima")
        try mac.directory.directory("root/opt/rancher-desktop/bin")

        let found = mac.left("io.rancherdesktop.app")
        let left = try #require(found)

        #expect(left.paths == ["/etc/sudoers.d/zzzzz-rancher-desktop-lima", "/opt/rancher-desktop"])
        #expect(left.command == "sudo rm -r /etc/sudoers.d/zzzzz-rancher-desktop-lima /opt/rancher-desktop")
    }

    @Test func namesOnlyWhatIsOnThisMac() throws {
        let mac = try Mac()
        try mac.directory.file("root/private/etc/paths.d/Wireshark")

        let found = mac.left("org.wireshark.Wireshark")
        let left = try #require(found)

        #expect(left.paths == ["/etc/paths.d/Wireshark"])
        #expect(left.ruleForSudo == nil)
        #expect(left.command == "sudo rm /etc/paths.d/Wireshark")
    }

    @Test func namesNothingForAnAppItDoesNotKnow() throws {
        let mac = try Mac()
        try mac.directory.file("root/private/etc/paths.d/postgresapp")

        #expect(mac.left("com.postgresapp.Postgres2")?.paths == ["/etc/paths.d/postgresapp"])
        #expect(mac.left("org.example.postgres") == nil)
    }

    @Test func anUninstallSaysWhatTheAppLeavesThereAndListsNoneOfItAsARow() async throws {
        let mac = try Mac()
        try mac.directory.file("root/private/etc/paths.d/postgresapp")
        let bundle = try mac.directory.directory("root/Applications/Postgres.app")
        let app = InstalledApp(url: bundle, bundleIdentifier: "com.postgresapp.Postgres2", name: "Postgres")

        let plan = await Uninstallation.prepare(app, installedApps: [app], environment: mac.environment)

        #expect(plan.leftInTheSystem?.paths == ["/etc/paths.d/postgresapp"])
        #expect(!plan.scan.leftovers.contains { $0.url.path(percentEncoded: false).contains("/etc/") })
        #expect(UninstallCommand.warnings(
            moving: [app.url], of: app, uninstallsItself: nil, leftInTheSystem: plan.leftInTheSystem,
            resettingPrivacy: false
        ) == [
            "Postgres leaves /etc/paths.d/postgresapp on this Mac after it goes, which only an administrator can remove. To remove it, run `sudo rm /etc/paths.d/postgresapp`.",
        ])
    }

    @Test func peelUninstallSaysWhatARuleForSudoLetsAnyoneDo() throws {
        let mac = try Mac()
        try mac.directory.file("root/private/etc/sudoers.d/zzzzz-rancher-desktop-lima")
        try mac.directory.directory("root/opt/rancher-desktop/bin")
        let app = InstalledApp(
            url: mac.directory.url.appending(path: "root/Applications/Rancher Desktop.app"),
            bundleIdentifier: "io.rancherdesktop.app",
            name: "Rancher Desktop"
        )
        let left = LeftInTheSystem.of(app, environment: mac.environment)

        #expect(UninstallCommand.warnings(
            moving: [app.url], of: app, uninstallsItself: nil, leftInTheSystem: left, resettingPrivacy: false
        ) == [
            "Rancher Desktop leaves /etc/sudoers.d/zzzzz-rancher-desktop-lima and /opt/rancher-desktop on this Mac after it goes, which only an administrator can remove. /etc/sudoers.d/zzzzz-rancher-desktop-lima is a rule that lets anyone run the programs it names as an administrator, without a password. To remove them, run `sudo rm -r /etc/sudoers.d/zzzzz-rancher-desktop-lima /opt/rancher-desktop`.",
        ])
        #expect(UninstallCommand.warnings(
            moving: [], of: app, uninstallsItself: nil, leftInTheSystem: left, resettingPrivacy: false
        ).isEmpty)
    }

    @Test func namesWhatACasksOwnUninstallStepsLeave() throws {
        let mac = try Mac()
        try mac.directory.file("root/private/etc/sudoers.d/battery")
        try mac.directory.file("root/private/etc/sudoers.d/zzzzz-rancher-desktop-lima")

        #expect(mac.left(cask: "battery")?.paths == ["/etc/sudoers.d/battery"])
        #expect(mac.left(cask: "rancher") == nil, "Homebrew's uninstall of Rancher Desktop deletes its rule")
        #expect(mac.left(cask: "battery", kind: .formula) == nil)
    }
}
