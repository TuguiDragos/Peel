import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct ProjectLibraryTests {
    @Test func scansAgainOnlyOnceItsLastScanIsOld() async throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ProjectLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try project("app", in: root)
        made.defaults.set([root.path(percentEncoded: false)], forKey: "projectFolders")
        let library = ProjectLibrary(defaults: made.defaults)

        await library.refreshUnlessScanned(within: .seconds(3_600))
        try project("tool", in: root)
        await library.refreshUnlessScanned(within: .seconds(3_600))
        let soon = library.groups?.map(\.name)
        await library.refreshUnlessScanned(within: .zero)

        #expect(soon == ["app"])
        #expect(library.groups?.map(\.name).sorted() == ["app", "tool"])
    }

    @Test func addsAFolderOnceWhenItIsAddedTwiceAtOnce() async throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ProjectLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try project("app", in: root)
        let library = ProjectLibrary(defaults: made.defaults)

        async let first: Void = library.add([root])
        async let second: Void = library.add([root])
        _ = await (first, second)

        #expect(library.folders == [root])
    }

    @Test func aMarkBeingWrittenShowsWhatWasClickedAndTakesNoOtherClick() async throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ProjectLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try project("app", in: root)
        made.defaults.set([root.path(percentEncoded: false)], forKey: "projectFolders")
        let (held, release) = AsyncStream.makeStream(of: Void.self)
        let library = ProjectLibrary(defaults: made.defaults) { _, _ in
            for await _ in held { break }
            return []
        }
        await library.refresh()
        let group = try #require(library.groups?.first)
        #expect(!library.isExcludedFromBackups(group))

        let change = Task { await library.setExcludedFromBackups(true, in: group) }
        let clock = ContinuousClock()
        let start = clock.now
        while !library.isChangingBackups(of: group), clock.now - start < .seconds(5) { await Task.yield() }

        #expect(library.isExcludedFromBackups(group))
        #expect(!library.canMarkForBackups(group))
        release.yield()
        release.finish()
        await change.value
        #expect(library.isExcludedFromBackups(group))
        #expect(!library.isChangingBackups(of: group))
        #expect(library.canMarkForBackups(group))
    }

    private func project(_ name: String, in root: URL) throws {
        let folder = root.appending(path: "\(name)/node_modules/left-pad", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "\(name)/package.json"))
        try Data("//".utf8).write(to: folder.appending(path: "index.js"))
    }
}
