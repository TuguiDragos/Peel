import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

/// Attacks on the scans that reach furthest: the nested search, the top of the home folder, hidden home files,
/// and `/Users/Shared`.
struct AttackScannerTests {
    private let tunewell = InstalledApp(
        url: URL(filePath: "/Applications/Tunewell.app"),
        bundleIdentifier: "net.example.client",
        name: "Tunewell"
    )

    private func environment(_ directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
    }

    private func paths(_ scan: LeftoverScan, _ directory: borrowing TemporaryDirectory) -> Set<String> {
        let root = directory.url.appending(path: "home", directoryHint: .isDirectory).path(percentEncoded: false)
        return Set(scan.leftovers.map { String($0.url.path(percentEncoded: false).dropFirst(root.count)) })
    }

    /// The nested search walks two levels into hidden folders in the home folder. It must not list what is
    /// already in the Trash, and the guard must not let it be moved again.
    @Test func nestedSearchWalksIntoTheTrash() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/.Trash/Tunewell/important.txt")
        try directory.directory("home/Library")

        let scan = await LeftoverScanner(environment: environment(directory)).scan(tunewell, installedApps: [tunewell])
        let guardian = RemovalGuard(environment: environment(directory))
        let inTheTrash = scan.leftovers.filter { $0.url.path(percentEncoded: false).contains("/.Trash/") }
        let removable = inTheTrash.filter { guardian.allowsRemoval(of: $0.url) }.map { $0.url.lastPathComponent }

        #expect(inTheTrash.isEmpty, "ATTACK SUCCEEDED: the scanner offers what is already in the Trash: \(paths(scan, directory))")
        #expect(removable.isEmpty, "and the guard allows removing it again: \(removable)")
    }

    /// The same walk must not list or preselect anything inside the folders the guard calls irreplaceable, such
    /// as `~/.ssh` and `~/.aws`.
    @Test func nestedSearchListsFilesInsideProtectedDotFolders() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/.ssh/Tunewell/id_ed25519")
        try directory.file("home/.aws/Tunewell/credentials")
        try directory.directory("home/Library")

        let scan = await LeftoverScanner(environment: environment(directory)).scan(tunewell, installedApps: [tunewell])
        let found = paths(scan, directory)
        let guardian = RemovalGuard(environment: environment(directory))

        let recommended = scan.leftovers.filter { $0.match.isRecommended }.map { $0.url.lastPathComponent }
        let removable = scan.leftovers.filter { guardian.allowsRemoval(of: $0.url) }.map { $0.url.lastPathComponent }

        #expect(found.isDisjoint(with: [".ssh/Tunewell", ".aws/Tunewell"]), "ATTACK SUCCEEDED: \(found) inside protected folders")
        #expect(recommended.isEmpty, "ATTACK SUCCEEDED: preselected inside protected folders: \(recommended)")
        // The guard is the last check: even if these were listed, it must refuse to move them.
        #expect(removable.isEmpty, "and the guard would let them go: \(removable)")
    }

    /// A symbolic link must not lead the nested search somewhere else, such as `~/Documents`.
    @Test func nestedSearchRefusesToFollowASymbolicLink() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Documents/Tunewell/thesis.txt")
        try directory.directory("home/Library/Application Support")
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "home/Library/Application Support/Vendor").path(percentEncoded: false),
            withDestinationPath: directory.url.appending(path: "home/Documents").path(percentEncoded: false)
        )
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "home/.vendor").path(percentEncoded: false),
            withDestinationPath: directory.url.appending(path: "home/Documents").path(percentEncoded: false)
        )

        let scan = await LeftoverScanner(environment: environment(directory)).scan(tunewell, installedApps: [tunewell])

        #expect(paths(scan, directory).isEmpty, "ATTACK SUCCEEDED: the nested search followed a link: \(paths(scan, directory))")
    }

    /// The top of the home folder is where the user keeps their own work. Orphaned Files looks at it, and the
    /// only thing it may name there is a folder an identifier claims: a name of the user's own says nothing.
    @Test func orphanScannerNamesOnlyWhatAnIdentifierClaimsInTheHomeFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/com.gone.app/notes.txt")
        try directory.file("home/Photos Backup/one.jpg")
        try directory.file("home/Tunewell/mine.txt")
        try directory.directory("home/Library")
        let scanner = OrphanScanner(environment: environment(directory)) { _ in false }

        let scan = await scanner.scan(installedApps: [tunewell])
        let found = scan.groups.flatMap { $0.items.map { $0.url.lastPathComponent } }

        #expect(found == ["com.gone.app"], "ATTACK SUCCEEDED: something of the user's own is reported as an orphan: \(found)")
    }

    /// Shortcuts keeps its data in a group container whose name has no `com.apple.` in it. Orphaned Files leaves it
    /// out because the guard refuses it, not because the Shortcuts app happens to claim it: here nothing does.
    @Test func orphanScannerNeverListsWhatTheGuardRefuses() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Group Containers/group.is.workflow.shortcuts/Shortcuts.sqlite")
        try directory.file("home/Library/Group Containers/group.com.gone.app/data.db")
        let scanner = OrphanScanner(
            environment: environment(directory),
            isRegisteredApp: { _ in false },
            systemApps: []
        )

        let found = await scanner.scan(installedApps: []).groups.map(\.identifier)

        #expect(found == ["com.gone.app"], "ATTACK SUCCEEDED: what the guard refuses is listed as an orphan: \(found)")
    }

    /// There are real apps called Documents, Downloads, and Public. The folders every account starts with are
    /// never theirs.
    @Test func neverClaimsTheFoldersEveryAccountStartsWith() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library")
        for name in ProtectedData.accountFolders {
            try directory.file("home/\(name)/something.txt")
        }

        for name in ProtectedData.accountFolders {
            let app = InstalledApp(url: URL(filePath: "/Applications/\(name).app"), bundleIdentifier: "com.example.\(name)", name: name)
            let scan = await LeftoverScanner(environment: environment(directory)).scan(app, installedApps: [app])

            #expect(paths(scan, directory).isEmpty, "ATTACK SUCCEEDED: an app called \(name) was handed ~/\(name): \(paths(scan, directory))")
        }
    }

    /// A name at the top of the home folder is a guess, so the folder is shown and never selected. Here it holds
    /// the user's own work under the app's name.
    @Test func aNameAtTheTopOfTheHomeFolderIsNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Tunewell/my own notes.txt")
        try directory.directory("home/Library")

        let scan = await LeftoverScanner(environment: environment(directory)).scan(tunewell, installedApps: [tunewell])
        let uninstallation = Uninstallation(app: tunewell, appSize: 0, appRequiresPrivileges: false, scan: scan)

        #expect(paths(scan, directory) == ["Tunewell"])
        #expect(scan.leftovers.first?.match.heldBack == .namedLikeTheApp)
        #expect(uninstallation.suggestedSelection(canUseHelper: true).map(\.lastPathComponent) == ["Tunewell.app"])
    }

    /// `/Users/Shared` holds what every account on the Mac uses. Matching only knows this account's apps.
    @Test func sharedFolderIsMatchedFromOneAccountsApps() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Users/Shared/net.example.client/library.db")
        try directory.directory("home/Library")

        let scan = await LeftoverScanner(environment: environment(directory)).scan(tunewell, installedApps: [tunewell])
        let recommended = scan.leftovers.filter(\.match.isRecommended).map { $0.url.path(percentEncoded: false) }

        #expect(recommended.isEmpty, "a folder shared with the other accounts on the Mac is preselected: \(recommended)")
    }
}
