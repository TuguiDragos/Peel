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

    @Test func saysHowMuchOfWhatItFoundPeelRecommends() {
        func artifact(_ name: String, size: Int64, isEnvironment: Bool = false) -> ProjectArtifact {
            let project = URL(filePath: "/Users/me/Code/app", directoryHint: .isDirectory)
            return ProjectArtifact(
                url: project.appending(path: name), project: project, name: name, tool: "npm", size: size,
                lastActivity: .now.addingTimeInterval(-60 * 60 * 24 * 60), hasGenericName: false,
                isEnvironment: isEnvironment
            )
        }
        func group(_ artifacts: [ProjectArtifact]) -> ProjectGroup {
            ProjectGroup(project: artifacts[0].project, name: "app", artifacts: artifacts)
        }
        let words = { (groups: [ProjectGroup]) in ProjectLibrary.summary(of: groups).map { String($0.characters) } }
        let built = artifact("node_modules", size: 6_000_000_000)
        let installed = artifact(".venv", size: 89_000_000_000, isEnvironment: true)

        let total = SizeTotal(known: 95_000_000_000, isComplete: true).text
        let recommended = SizeTotal(known: 6_000_000_000, isComplete: true).text
        #expect(words([group([built, installed])]) == String(AttributedString(
            localized: "\(total) in ^[\(1) project](inflect: true), \(recommended) of it recommended."
        ).characters))
        let onlyInstalled = SizeTotal(known: 89_000_000_000, isComplete: true).text
        #expect(words([group([installed])]) == String(AttributedString(
            localized: "\(onlyInstalled) in ^[\(1) project](inflect: true), none of it recommended."
        ).characters))
        #expect(words([group([built])]) == String(AttributedString(
            localized: "\(recommended) in ^[\(1) project](inflect: true)."
        ).characters), "all of it recommended")
        #expect(words([]) == nil)
    }

    private func project(_ name: String, in root: URL) throws {
        let folder = root.appending(path: "\(name)/node_modules/left-pad", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "\(name)/package.json"))
        try Data("//".utf8).write(to: folder.appending(path: "index.js"))
    }
}
