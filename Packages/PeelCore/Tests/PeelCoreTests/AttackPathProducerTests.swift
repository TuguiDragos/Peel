import Foundation
@testable import PeelCore
import Testing

/// Attacks through the places removable paths come from (Homebrew casks, installer receipts, and the developer
/// cache table), with a protected path written in another case or reached through a link.
struct AttackPathProducerTests {
    private func link(_ target: String, at url: URL) throws {
        try FileManager.default.createSymbolicLink(atPath: url.path(percentEncoded: false), withDestinationPath: target)
    }

    private func environment(_ directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
    }

    /// `PathPattern.expand` keeps the caller's spelling and follows links, so it must drop a protected path
    /// however it is written and wherever a link leads.
    @Test func expandKeepsTheCallersSpellingAndFollowsLinks() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/Library/Mobile Documents/com~apple~CloudDocs/dotfiles/gcloud/logs/keep.txt")
        try link(
            "Library/Mobile Documents/com~apple~CloudDocs/dotfiles",
            at: home.appending(path: ".config")
        )

        let cased = PathPattern.expand("Library/mobile documents/com~apple~CloudDocs/dotfiles", home: home)
        #expect(cased.first?.path(percentEncoded: false).contains("mobile documents") != true, "expand hands back a spelling the guard cannot read")

        let throughLink = PathPattern.expand(".config/gcloud/logs", home: home)
        #expect(throughLink.isEmpty, "expand walked through a symbolic link out of the home folder")
    }

    /// The whole chain: a cask names an iCloud Drive folder in another case. It must not be listed, preselected,
    /// or moved.
    @Test func aCaskPathInAnotherCaseReachesICloudDrive() async throws {
        let directory = try TemporaryDirectory()
        let real = try directory.file("home/Library/Mobile Documents/iCloud~com~acme~Notes/Documents/journal.txt")
        try directory.directory("home/Library/Caches")
        let app = InstalledApp(url: directory.url.appending(path: "Applications/Notes.app"), bundleIdentifier: "com.acme.notes", name: "Notes")
        let cask = HomebrewPackage(
            name: "acme-notes",
            kind: .cask,
            appNames: ["Notes.app"],
            leftoverPatterns: ["~/Library/mobile documents/iCloud~com~acme~Notes"]
        )

        let uninstallation = await Uninstallation.prepare(
            app,
            installedApps: [app],
            casks: [cask],
            environment: environment(directory)
        )
        let named = uninstallation.scan.leftovers.map { $0.url.path(percentEncoded: false) }
        #expect(named.isEmpty, "the cask path was accepted: \(named)")

        let selection = uninstallation.suggestedSelection(canUseHelper: false)
        #expect(!selection.contains(where: { $0.lastPathComponent == "iCloud~com~acme~Notes" }), "an iCloud Drive folder is preselected")

        let trash = try directory.directory("FakeTrash")
        let service = TrashService(environment: environment(directory)) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        _ = await service.trash(uninstallation.removalOrder(of: selection))
        #expect(
            FileManager.default.fileExists(atPath: real.path(percentEncoded: false)),
            "ATTACK SUCCEEDED: the iCloud Drive folder was moved, which deletes it on every device"
        )
    }

    /// The other third-party source of hand-written paths: an installer package's own file list.
    @Test func aPackageReceiptCanNameAProtectedTreeInAnotherCase() throws {
        let files = [
            "Users/someone/Library/mobile documents/com~apple~CloudDocs/Vendor",
            "Users/someone/Library/mobile documents/com~apple~CloudDocs/Vendor/data.db",
        ]
        let items = PackageReceipts.topLevel(files: files, installLocation: "/", exists: { _ in true }).offered

        #expect(items.isEmpty, "ATTACK SUCCEEDED: a package receipt produced \(items)")
    }

    /// Dotfiles kept in iCloud Drive and symlinked into the home folder, which is a common arrangement.
    @Test func developerCachesFollowASymlinkedDotfileFolder() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let real = try directory.file("home/Library/Mobile Documents/com~apple~CloudDocs/dotfiles/gcloud/logs/notes.txt")
        try link("Library/Mobile Documents/com~apple~CloudDocs/dotfiles", at: home.appending(path: ".config"))

        let environments = await DeveloperCaches.scan(in: SearchEnvironment(homeDirectory: home, rootDirectory: home))
        let offered = environments.flatMap(\.locations).map { $0.url.path(percentEncoded: false) }
        #expect(!offered.contains { $0.hasSuffix("/.config/gcloud/logs") }, "the developer page offers a path that lands in iCloud Drive")

        guard let url = environments.flatMap(\.locations).first(where: { $0.url.lastPathComponent == "logs" })?.url
        else { return }
        let trash = try directory.directory("FakeTrash")
        let service = TrashService(environment: environment(directory)) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        let result = await service.trash([url])
        let reasons = result.failures.map(\.reason)
        #expect(reasons == [.guarded(.protectedLocation)], "the guard let a symlinked path through")
        #expect(
            FileManager.default.fileExists(atPath: real.path(percentEncoded: false)),
            "ATTACK SUCCEEDED: an iCloud Drive folder was removed through a symbolic link"
        )
    }
}
