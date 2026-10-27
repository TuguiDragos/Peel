import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct PluginLibraryTests {
    private final class Reads {
        var count = 0
    }

    @Test func takesAMovedPlugInOffTheListBeforeReadingItAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "PluginLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        let trash = root.appending(path: "Trash", directoryHint: .isDirectory)
        let echo = home.appending(path: "Library/Audio/Plug-Ins/Components/Echo.component", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: echo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let plugin = Plugin(
            url: echo, name: "Echo", bundleIdentifier: nil, version: nil, category: .audioUnits,
            isInstalledForAllUsers: false, size: 1, requiresPrivileges: false, refusal: nil
        )
        let reads = Reads()
        let library = PluginLibrary(
            scan: { _ in
                reads.count += 1
                return PluginScan(plugins: [plugin])
            },
            trashService: { _ in
                TrashService(
                    environment: SearchEnvironment(
                        homeDirectory: home, rootDirectory: root.appending(path: "root", directoryHint: .isDirectory)
                    ),
                    moveToTrash: { url in
                        let destination = trash.appending(path: UUID().uuidString)
                        try FileManager.default.moveItem(at: url, to: destination)
                        return destination
                    }
                )
            }
        )
        await library.refresh()
        library.selection = plugin.id

        let result = await library.moveToTrash(plugin) { _ in }

        #expect(result.trashed.map(\.originalURL) == [echo])
        #expect(library.plugins?.isEmpty == true)
        #expect(library.selection == nil)
        #expect(reads.count == 1, "the list is read again only once the page has said how the move went")
    }
}
