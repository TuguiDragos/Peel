import Foundation
@testable import PeelCore
import Testing

struct ProjectArtifactsTests {
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...30 {
            try directory.file("Code/Project \(index)/package.json", contents: Data("{}".utf8))
            try directory.file("Code/Project \(index)/node_modules/left-pad/index.js", contents: Data("//".utf8))
        }
        let unanswered = Unanswered()

        let stop = try await unanswered.stop {
            _ = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Code", directoryHint: .isDirectory)], exclusions: .none, measure: unanswered.measure)
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }

    /// Full Disk Access does not open a folder closed by ordinary file permissions, so the scan must not ask for it.
    /// The Time Machine checkbox marks only what a build certainly makes again, and never an artifact Time
    /// Machine already leaves out through a folder above it, whose exclusion is not its own to change. A project
    /// with nothing else gives the checkbox nothing to do.
    @Test func marksForBackupsOnlyWhatABuildCertainlyMakesAgain() {
        func artifact(_ name: String, isGeneric: Bool) -> ProjectArtifact {
            ProjectArtifact(
                url: URL(filePath: "/Users/x/Code/App/\(name)"), project: URL(filePath: "/Users/x/Code/App"), name: name,
                tool: "tool", size: 10, lastActivity: nil, hasGenericName: isGeneric, isEnvironment: false
            )
        }
        let target = artifact("target", isGeneric: true)
        let modules = artifact("node_modules", isGeneric: false)
        let pods = artifact("Pods", isGeneric: false)

        #expect(ProjectArtifacts.markableForBackups([target], excludedFromAbove: []).isEmpty)
        #expect(ProjectArtifacts.markableForBackups([target, modules, pods], excludedFromAbove: [pods.url]) == [modules.url])
        #expect(ProjectArtifacts.markableForBackups([modules], excludedFromAbove: [modules.url]).isEmpty)
    }

    @Test func doesNotBlameFullDiskAccessForOrdinaryPermissions() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Code/app/package.json", bytes: 16)
        try directory.setPermissions(0, of: "Code")
        defer { try? directory.setPermissions(0o755, of: "Code") }

        let scan = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Code", directoryHint: .isDirectory)])
        #expect(scan.artifacts.isEmpty)
        #expect(!scan.needsFullDiskAccess)
    }

    private func age(_ url: URL, days: Int) throws {
        let date = Date.now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let item as URL in enumerator {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: item.path(percentEncoded: false))
        }
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// A `node_modules` folder with no `package.json` beside it is the user's own folder, not an artifact.
    @Test func findsAnArtifactOnlyBesideTheFileThatMakesIt() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Projects/site/package.json", bytes: 16)
        try directory.file("Projects/site/node_modules/left-pad/index.js", bytes: 400_000)
        try directory.file("Projects/notes/node_modules/photos/holiday.jpg", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Projects")]).artifacts

        #expect(found.map(\.project.lastPathComponent) == ["site"])
        #expect(found.first?.name == "node_modules")
        #expect(found.first?.tool == "npm")
        #expect(try #require(found.first?.size) >= 400_000)
        #expect(found.first?.isRecommended == true)
    }

    /// A large `node_modules` is the folder most likely to run out of time. Its size is then unknown, not zero,
    /// so it is listed first and never selected for the user.
    @Test func anArtifactThatDidNotAnswerInTimeIsNotReadAsEmpty() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Projects/site/package.json", bytes: 16)
        try directory.file("Projects/site/node_modules/left-pad/index.js", bytes: 400_000)
        try directory.file("Projects/tool/Package.swift", bytes: 16)
        try directory.file("Projects/tool/.build/debug/tool", bytes: 800_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Projects")], exclusions: .none) { url in
            url.lastPathComponent == "node_modules" ? nil : await FileSize.allocatedSize(of: url, within: FileSize.budget)
        }.artifacts

        #expect(found.map(\.name) == ["node_modules", ".build"])
        #expect(found.first?.size == nil)
        #expect(found.first?.isRecommended == false, "what Peel could not measure is never selected for the user")
        #expect(found.last?.isRecommended == true)
        #expect(try #require(found.last?.size) >= 800_000)
    }

    @Test func showsGenericNamesButNeverSelectsThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("rust/Cargo.toml", bytes: 16)
        try directory.file("rust/target/debug/app", bytes: 400_000)
        try directory.file("swift/Package.swift", bytes: 16)
        try directory.file("swift/.build/debug/app", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        let target = try #require(found.first { $0.name == "target" })
        let build = try #require(found.first { $0.name == ".build" })

        #expect(target.hasGenericName)
        #expect(!target.isRecommended)
        #expect(!build.hasGenericName)
        #expect(build.isRecommended)
    }

    @Test func leavesProjectsAloneWhileSomeoneIsWorkingInThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("live/package.json", bytes: 16)
        try directory.file("live/node_modules/dep/index.js", bytes: 400_000)
        try directory.file("old/package.json", bytes: 16)
        try directory.file("old/node_modules/dep/index.js", bytes: 400_000)
        try age(directory.url, days: 60)
        try directory.file("live/src/main.js", bytes: 16)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        let live = try #require(found.first { $0.project.lastPathComponent == "live" })
        let old = try #require(found.first { $0.project.lastPathComponent == "old" })

        #expect(live.isRecentlyActive)
        #expect(!live.isRecommended)
        #expect(!old.isRecentlyActive)
        #expect(old.isRecommended)
    }

    /// Walking into `node_modules` would find thousands of nested copies and make the scan very slow.
    @Test func neverWalksIntoAnArtifactItAlreadyFound() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("app/package.json", bytes: 16)
        try directory.file("app/node_modules/dep/package.json", bytes: 16)
        try directory.file("app/node_modules/dep/node_modules/inner/index.js", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        #expect(found.count == 1)
        #expect(found.first?.url.path(percentEncoded: false).hasSuffix("/app/node_modules") == true)
    }

    @Test func honorsExclusions() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("app/package.json", bytes: 16)
        let modules = try directory.directory("app/node_modules")
        try directory.file("app/node_modules/dep/index.js", bytes: 400_000)
        try age(directory.url, days: 60)

        #expect(await ProjectArtifacts.scan(roots: [directory.url], exclusions: Exclusions(paths: [modules])).artifacts.isEmpty)
        #expect(await ProjectArtifacts.scan(roots: [directory.url]).artifacts.count == 1)
    }

    /// A hidden folder is a tool's own store. `~/.npm` alone can hold thousands of `node_modules`, and those
    /// belong to the Developer page.
    @Test func neverLooksInsideAHiddenFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".npm/_npx/abc/package.json", bytes: 16)
        try directory.file(".npm/_npx/abc/node_modules/dep/index.js", bytes: 400_000)
        try directory.file("work/app/package.json", bytes: 16)
        try directory.file("work/app/node_modules/dep/index.js", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        #expect(found.map(\.project.lastPathComponent) == ["app"])
    }

    /// A virtual environment holds installed packages, not build output, so it is never selected for the user.
    @Test func showsVirtualEnvironmentsButNeverSelectsThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("py/pyproject.toml", bytes: 16)
        try directory.file("py/.venv/lib/python/site.py", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        let venv = try #require(found.first)
        #expect(venv.isEnvironment)
        #expect(!venv.hasGenericName)
        #expect(!venv.isRecommended)
    }

    /// `.terraform` keeps the selected workspace and the last backend configuration, which `terraform init`
    /// does not bring back.
    @Test func showsTerraformsFolderButNeverSelectsIt() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("infra/main.tf", bytes: 16)
        try directory.file("infra/.terraform/providers/registry/plugin", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = try #require(await ProjectArtifacts.scan(roots: [directory.url]).artifacts.first)

        #expect(found.name == ".terraform")
        #expect(found.isEnvironment)
        #expect(!found.isRecommended)
    }

    /// Without a reason, the page would say "Nothing Built Here" about a folder it never searched.
    @Test func saysWhyAFolderCannotBeSearched() throws {
        let directory = try TemporaryDirectory()
        let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)

        #expect(ProjectArtifacts.refusal(for: home, home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/Volumes/Disk"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Code"), home: home) == .inTheCloud)
        #expect(ProjectArtifacts.refusal(for: directory.url.appending(path: "nothing-here"), home: home) == .notAFolder)
        #expect(ProjectArtifacts.refusal(for: try directory.directory("Code"), home: home) == nil)

        // The same folders under other spellings that macOS also accepts.
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/users/x"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/System/Volumes/Data/Users/x"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/System/Volumes/Data"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: home.appending(path: "Library/CLOUDSTORAGE/Dropbox"), home: home) == .inTheCloud)
    }

    @Test func refusesRootsThatAreTooBroadOrNotOurs() {
        #expect(!ProjectArtifacts.isSearchable(URL(filePath: "/")))
        #expect(!ProjectArtifacts.isSearchable(URL(filePath: "/Users")))
        #expect(!ProjectArtifacts.isSearchable(URL(filePath: "/Users/x/Library/Mobile Documents/com~apple~Pages")))
        #expect(!ProjectArtifacts.isSearchable(URL(filePath: "/Users/x/Library/CloudStorage/Dropbox")))
        #expect(!ProjectArtifacts.isSearchable(URL(filePath: "/Users/x/does-not-exist")))
    }

    @Test func everyDefinitionNamesAMarkerAndATool() {
        for definition in ProjectArtifacts.definitions {
            #expect(!definition.name.isEmpty)
            #expect(!definition.markers.isEmpty, "\(definition.name) has no marker")
            #expect(!definition.tool.isEmpty)
            #expect(!definition.name.contains("/"))
        }
    }

    /// `/Users/someone` and `/Volumes/Disk` have two path components each, like a real project root, so
    /// counting components alone cannot refuse them.
    @Test func refusesAHomeFolderAndAVolumeRoot() throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("Users/someone")
        try directory.directory("Users/someone/Projects")

        #expect(!ProjectArtifacts.isSearchable(URL(filePath: "/Users/someone"), home: home))
        #expect(!ProjectArtifacts.isSearchable(URL(filePath: "/Volumes/Disk"), home: home))
        #expect(!ProjectArtifacts.isSearchable(home, home: home))
        #expect(ProjectArtifacts.isSearchable(home.appending(path: "Projects"), home: home))
    }

    /// An Electron app ships `package.json` beside `node_modules` inside its own bundle. That matches the marker
    /// rule, but nothing inside an app may be removed.
    @Test func neverLooksInsideAnAppBundle() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Tools/Editor.app/Contents/Resources/app/package.json")
        try directory.file("Tools/Editor.app/Contents/Resources/app/node_modules/left-pad/index.js", bytes: 1_000)

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Tools", directoryHint: .isDirectory)]).artifacts

        #expect(found.isEmpty, "part of an installed app was offered")
    }

    /// A project too big to read to the end says nothing about when it was last worked on, and what is not
    /// known is never selected for the user.
    @Test func doesNotSelectAProjectItCouldNotReadToTheEnd() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Project/package.json")
        try directory.file("Project/node_modules/left-pad/index.js", bytes: 1_000)
        for index in 0..<(ProjectArtifacts.maximumActivitySamples + 10) {
            try directory.file("Project/src/file\(index).txt", bytes: 1)
        }
        let old = Date(timeIntervalSinceNow: -60 * 24 * 60 * 60)
        var aged = ["Project", "Project/src", "Project/package.json"]
        aged += (0..<(ProjectArtifacts.maximumActivitySamples + 10)).map { "Project/src/file\($0).txt" }
        for path in aged.reversed() {
            try FileManager.default.setAttributes(
                [.modificationDate: old],
                ofItemAtPath: directory.url.appending(path: path).path(percentEncoded: false)
            )
        }

        let artifact = try #require(await ProjectArtifacts.scan(roots: [directory.url]).artifacts.first)

        #expect(!artifact.lastActivityIsCertain)
        #expect(!artifact.isRecommended)
    }

    /// Every git command that changes something writes under `.git`, so three files there tell when the whole
    /// repository was last used, without reading a sample of its files.
    @Test func readsWhenTheRepositoryWasLastUsed() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Project/package.json")
        let old = Date(timeIntervalSinceNow: -60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: try directory.file("Project/src/main.swift").path(percentEncoded: false))
        try directory.file("Project/.git/index")

        let activity = ProjectArtifacts.lastActivity(in: directory.url.appending(path: "Project", directoryHint: .isDirectory), ignoring: ["node_modules"])

        #expect(activity.isCertain)
        #expect(try #require(activity.date).timeIntervalSinceNow > -60)
    }
}
