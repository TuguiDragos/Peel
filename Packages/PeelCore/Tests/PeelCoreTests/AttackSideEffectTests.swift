import Foundation
@testable import PeelCore
import Testing

/// Side effects `TrashService` performs after moving a file. Nothing here runs `defaults` or `launchctl`: the
/// tests only check what would be handed to them.
struct AttackSideEffectTests {
    /// Trashing a copy of a plist kept elsewhere, such as in a backup, must not run `defaults delete` for the app
    /// it was copied from: that would clear the settings the app is still using.
    @Test func trashingABackupCopyWipesTheLiveDomain() throws {
        let home = URL(filePath: "/Users/someone")
        let copies = [
            home.appending(path: "Documents/Backups/2024-05/Preferences/com.adobe.Photoshop.plist"),
            home.appending(path: "Desktop/old mac/Library/Preferences/com.omnigroup.OmniFocus4.plist"),
            URL(filePath: "/Volumes/Backup/Preferences/com.readdle.PDFExpert.plist"),
            home.appending(path: "Downloads/Preferences/ByHost/com.vendor.tool.0A1B2C3D-1111-2222-3333-444455556666.plist"),
        ]

        // Judged against the home the copies sit in, so what refuses them is where they are, not whose they are.
        let domains = PreferenceCleanup.domains(for: copies, home: home)
        #expect(domains.isEmpty, "ATTACK SUCCEEDED: trashing copies would run `defaults delete` for \(domains.map(\.name))")
    }

    /// The same for launchd: trashing a backup copy of an agent must not stop the agent that is running. The
    /// copies are real files that declare a job, so only where they sit can refuse them.
    @Test func trashingABackupCopyStopsTheLiveAgent() throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )
        func plist(_ path: String, label: String) throws -> URL {
            try directory.file(
                path,
                contents: PropertyListSerialization.data(fromPropertyList: ["Label": label], format: .xml, options: 0)
            )
        }
        let live = try plist("home/Library/LaunchAgents/com.vendor.updater.plist", label: "com.vendor.updater")
        let copies = [
            try plist("home/Documents/backup/LaunchAgents/com.vendor.updater.plist", label: "com.vendor.updater"),
            try plist("root/Volumes/Backup/LaunchDaemons/com.vendor.daemon.plist", label: "com.vendor.daemon"),
        ]

        #expect(LaunchdCleanup.jobs(for: [live], environment: environment).map(\.label) == ["com.vendor.updater"])
        let jobs = LaunchdCleanup.jobs(for: copies, environment: environment)
        #expect(jobs.isEmpty, "ATTACK SUCCEEDED: trashing copies would boot out \(jobs.map(\.label))")
    }

    /// A job is stopped by its label once its file has moved, and a file can declare a label macOS itself uses.
    /// `com.openssh.ssh-agent` is one of macOS's own agents, and its label says nothing about Apple: moving a copy
    /// that declares it must not stop the one macOS runs.
    @Test func movingACopyOfMacOSsOwnAgentStopsNothing() throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )
        let copy = try directory.file(
            "home/Library/LaunchAgents/ssh.plist",
            contents: PropertyListSerialization.data(fromPropertyList: ["Label": "com.openssh.ssh-agent"], format: .xml, options: 0)
        )

        let jobs = LaunchdCleanup.jobs(for: [copy], environment: environment)

        #expect(jobs.isEmpty, "ATTACK SUCCEEDED: moving a copy would boot out macOS's own \(jobs.map(\.label))")
    }

    /// The same case, reached the way a user would: cleaning duplicates in a folder of backed-up plists. After the
    /// move, `TrashService.trash` hands the moved files to `PreferenceCleanup`, which must find no domain in them.
    @Test func duplicateCleaningReachesTheLiveDomain() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let contents = Data((0..<4_000).map { _ in UInt8.random(in: 0...255) })
        try directory.file("home/Documents/Backups/Preferences/com.adobe.Photoshop.plist", contents: contents)
        try directory.file("home/Desktop/com.adobe.Photoshop.plist", contents: contents)

        let scan = try await DuplicateFinder(homeDirectory: home).scan(.everySize(in: [home]))
        let selected = Array(scan.suggestedSelection)
        #expect(!selected.isEmpty)

        let domains = PreferenceCleanup.domains(for: selected, home: home)
        #expect(domains.isEmpty, "ATTACK SUCCEEDED: cleaning duplicates would run `defaults delete` for \(domains.map(\.name))")
    }
}
