import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// Each list filters on what its rows show. These check that the right things match, and that the wrong
/// ones don't: a filter that matches everything is as useless as one that matches nothing.
struct SearchingTests {
    private func duplicates(_ paths: String...) -> DuplicateGroup {
        DuplicateGroup(
            id: paths[0],
            files: paths.map {
                DuplicateFile(url: URL(filePath: $0), size: 10, reclaimableSize: 10, allocatedSize: 10, identity: FileIdentity(stat()))
            }
        )
    }

    /// The row names only the first copy, but the group is all of them.
    @Test func findsADuplicateByAnyOfItsCopies() {
        let group = duplicates("/Users/x/Documents/Report.pdf", "/Users/x/Desktop/Report copy.pdf")

        #expect(group.matches("Report"))
        #expect(group.matches("copy"))
        #expect(group.matches("Desktop"))
        #expect(!group.matches("invoice"))
    }

    @Test func findsABuildFolderByItsProjectToolOrName() {
        let artifact = ProjectArtifact(
            url: URL(filePath: "/Users/x/Developer/Peel/node_modules"),
            project: URL(filePath: "/Users/x/Developer/Peel"),
            name: "node_modules",
            tool: "npm",
            size: 10,
            lastActivity: nil,
            hasGenericName: false,
            isEnvironment: false
        )

        #expect(artifact.matches("Peel"))
        #expect(artifact.matches("npm"))
        #expect(artifact.matches("node_mod"))
        #expect(!artifact.matches("DerivedData"))
    }

    @Test func findsAnICloudFileByNameFolderOrPath() {
        let file = CloudFile(
            url: URL(filePath: "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/Muzica FARA NUME.mov"),
            name: "Muzica FARA NUME.mov",
            container: "iCloud Drive",
            size: 10,
            modified: nil
        )

        #expect(file.matches("muzica"))
        #expect(file.matches("CloudDocs"))
        #expect(file.matches("iCloud"))
        #expect(!file.matches("Wallpaper"))
    }

    @Test func findsIntelSoftwareByNameOrTheAppItSitsIn() {
        let finding = IntelFinding(
            url: URL(filePath: "/Applications/Photoshop.app/Contents/PlugIns/Widget.plugin"),
            kind: .plugin,
            name: "Widget.plugin",
            owner: "Photoshop",
            size: 10,
        )

        #expect(finding.matches("widget"))
        #expect(finding.matches("photoshop"))
        #expect(!finding.matches("Safari"))
    }

    @Test func ignoresCaseAndAccentsTheWayFinderDoes() {
        let file = CloudFile(
            url: URL(filePath: "/Users/x/Documents/Ședință.pages"),
            name: "Ședință.pages",
            container: "iCloud Drive",
            size: 10,
            modified: nil
        )

        #expect(file.matches("sedinta"))
        #expect(file.matches("ȘEDINȚĂ"))
    }

    @Test func anEmptyQueryKeepsEverything() {
        #expect(duplicates("/a/b.txt").matches(""))
        #expect(CloudFile(url: URL(filePath: "/a"), name: "a", container: "c", size: 1, modified: nil).matches(""))
        #expect(IntelFinding(url: URL(filePath: "/a"), kind: .app, name: "a", owner: nil, size: 1).matches(""))
    }

    /// File Search is for finding what the user made. What an app keeps in a Library folder is listed last and
    /// never selected, and Duplicates skips those folders for the same reason.
    @Test func marksWhatAnAppKeepsForItself() {
        let appData = FileSearch.AppDataFolders(home: URL(filePath: "/Users/x", directoryHint: .isDirectory))

        #expect(appData.holds("/Users/x/Library/Application Support/Thing/data.db"))
        #expect(appData.holds("/Library/Application Support/Thing/data.db"))
        #expect(appData.holds("/System/Library/Fonts/Helvetica.ttc"))
        #expect(!appData.holds("/Users/x/Documents/Letter.pages"))
        #expect(!appData.holds("/Users/x/Librarything/notes.txt"))
    }

    /// A result list can be open for hours. A file written again under the same name is another file, and the
    /// row still shows what the old one was.
    @Test func movesNothingThatChangedSinceTheSearch() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("notes.txt", bytes: 1_000)
        let listed = FoundFile(
            url: url,
            size: 1_000,
            modificationDate: .distantPast,
            requiresPrivileges: false,
            identity: FileIdentity.of(url)
        )
        try Data(repeating: 7, count: 2_000).write(to: url)
        let moved = Mutex<[URL]>([])
        let service = TrashService(environment: SearchEnvironment(homeDirectory: directory.url, rootDirectory: directory.url)) { url in
            moved.withLock { $0.append(url) }
            return url
        }

        let result = await FileSearch.trash([listed], using: service)

        #expect(moved.withLock { $0 }.isEmpty)
        #expect(result.failures.map(\.reason) == [.changedSinceScan])
    }
}
