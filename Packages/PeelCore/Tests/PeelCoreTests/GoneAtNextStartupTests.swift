import Foundation
@testable import PeelCore
import Testing

struct GoneAtNextStartupTests {
    private func marked() throws -> [URL] {
        let temporary = try #require(SearchEnvironment.current.userTemporaryDirectory)
        let entries = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
        let marked = entries.filter { FileAccess.cannotBeRemoved($0) && Identifier.isValid($0.lastPathComponent) }
        try #require(!marked.isEmpty, "nothing marked in \(temporary.path())")
        return marked
    }

    private func environment(in directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory),
            userTemporaryDirectory: SearchEnvironment.current.userTemporaryDirectory
        )
    }

    @Test func anUninstallShowsWhatMacOSRemovesAtTheNextStartupAndSelectsNoneOfIt() async throws {
        let directory = try TemporaryDirectory()
        let name = try #require(try marked().first).lastPathComponent
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: name, name: "Example",
            isSignedByTheAppStore: true
        )

        let plan = await Uninstallation.prepare(app, installedApps: [app], environment: environment(in: directory))

        let row = try #require(plan.scan.leftovers.first { $0.url.lastPathComponent == name }, "\(name)")
        #expect(row.match.heldBack == .goneAtNextStartup)
        #expect(row.match.heldBack?.cannotBeMoved == true)
        #expect(!plan.suggestedSelection(canUseHelper: true).contains(row.url))
    }

    @Test func orphanedFilesShowsWhatMacOSRemovesAtTheNextStartupAndMovesNoneOfIt() async throws {
        let directory = try TemporaryDirectory()
        let names = Set(try marked().map(\.lastPathComponent))
        let gone = names.map { name in
            RememberedApp(
                bundleIdentifier: name, name: "Example", teamIdentifier: nil,
                lastSeen: .now.addingTimeInterval(-86_400), lastPath: "/Applications/Example.app",
                goneSince: .now.addingTimeInterval(-86_400), isSignedByTheAppStore: true
            )
        }

        let scan = await OrphanScanner(environment: environment(in: directory)) { _ in false }
            .scan(installedApps: [], remembered: gone)

        let groups = scan.groups.filter { $0.items.contains { names.contains($0.url.lastPathComponent) } }
        try #require(!groups.isEmpty)
        for item in groups.flatMap(\.items) {
            #expect(item.heldBack == .goneAtNextStartup, "\(item.url.lastPathComponent)")
        }
        #expect(groups.allSatisfy { $0.isLeftAlone && $0.movable(canUseHelper: true).isNothing })
    }

    @Test func onlyTheTemporaryFolderIsEmptiedAtStartup() async throws {
        let directory = try TemporaryDirectory()
        let folder = try #require(try marked().first)
        func reason(_ kind: SearchLocation.Kind) async -> HoldBack? {
            await LeftoverScanner.leftover(
                at: folder,
                kind: kind,
                match: LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: []),
                parent: ParentAccess(folder.deletingLastPathComponent()),
                home: directory.url.appending(path: "home").path(percentEncoded: false),
                root: directory.url.appending(path: "root").path(percentEncoded: false),
                measure: { _ in FolderContents(size: 0, holdsRepository: false, couldNotBeRead: false) }
            ).match.heldBack
        }

        #expect(await reason(.temporaryItems) == .goneAtNextStartup)
        #expect(await reason(.caches) != .goneAtNextStartup)
    }
}
