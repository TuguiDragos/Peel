import Foundation
@testable import PeelCore
import Testing

struct GitIndexTests {
    enum Form: String, CaseIterable, Sendable {
        case version2, version3, version4, sha256, splitIndex, separateGitDirectory
    }

    @Test(arguments: Form.allCases)
    func readsWhatGitTracksInEveryIndexItWrites(_ form: Form) async throws {
        let directory = try TemporaryDirectory()
        let project = try makeProject(in: directory)
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        switch form {
        case .sha256:
            try await git.run("init", "-q", "--object-format=sha256", in: project)
        case .separateGitDirectory:
            let store = directory.url.appending(path: "store").path(percentEncoded: false)
            try await git.run("init", "-q", "--separate-git-dir", store, in: project)
        default:
            try await git.run("init", "-q", in: project)
        }
        if form == .version3 {
            try await git.run("add", "Podfile", "src", in: project)
            try await git.run("add", "-N", "Pods", in: project)
        } else {
            try await git.run("add", "Podfile", "Pods", "src", in: project)
        }
        if form == .version4 { try await git.run("update-index", "--index-version", "4", in: project) }
        if form == .splitIndex { try await git.run("update-index", "--split-index", in: project) }

        let repository = try #require(GitIndex.repository(containing: project))
        let written = try Data(contentsOf: repository.gitDirectory.appending(path: "index"))
        #expect(written.dropFirst(7).first == (form == .version3 ? 3 : form == .version4 ? 4 : 2))
        let store = repository.gitDirectory.path(percentEncoded: false)
        let shared = try FileManager.default.contentsOfDirectory(atPath: store)
        #expect(shared.contains { $0.hasPrefix("sharedindex.") } == (form == .splitIndex))

        let index = try #require(GitIndex.read(repository))
        #expect(index.tracksSomething(atOrInside: project.appending(path: "Pods"), of: repository))
        #expect(index.tracksSomething(atOrInside: project.appending(path: "Pods/Foo"), of: repository))
        #expect(index.tracksSomething(atOrInside: project.appending(path: "src"), of: repository))
        #expect(!index.tracksSomething(atOrInside: project.appending(path: "Other"), of: repository))
    }

    @Test func readsTheIndexOfAWorktree() async throws {
        let directory = try TemporaryDirectory()
        let project = try makeProject(in: directory)
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        try await git.run("init", "-q", in: project)
        try await git.run("add", "Podfile", "Pods", "src", in: project)
        try await git.run("commit", "-q", "-m", "One", in: project)
        let worktree = directory.url.appending(path: "Worktree")
        try await git.run("worktree", "add", "-q", worktree.path(percentEncoded: false), in: project)

        let repository = try #require(GitIndex.repository(containing: worktree.appending(path: "src")))
        #expect(repository.gitDirectory.deletingLastPathComponent().lastPathComponent == "worktrees")
        let index = try #require(GitIndex.read(repository))
        #expect(index.tracksSomething(atOrInside: worktree.appending(path: "Pods"), of: repository))
    }

    @Test func aSparseIndexTracksWhatItLeavesOut() async throws {
        let directory = try TemporaryDirectory()
        let project = try makeProject(in: directory)
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        try await git.run("init", "-q", in: project)
        try await git.run("add", "Podfile", "Pods", "src", in: project)
        try await git.run("commit", "-q", "-m", "One", in: project)
        try await git.run("sparse-checkout", "set", "--cone", "--sparse-index", "src", in: project)
        #expect(!FileManager.default.fileExists(atPath: project.appending(path: "Pods").path(percentEncoded: false)))
        _ = try directory.file("App/Pods/Foo/Foo.m")

        let repository = try #require(GitIndex.repository(containing: project))
        let index = try #require(GitIndex.read(repository))
        #expect(index.tracksSomething(atOrInside: project.appending(path: "Pods"), of: repository))
        #expect(index.tracksSomething(atOrInside: project.appending(path: "Pods/Foo"), of: repository))
        #expect(!index.tracksSomething(atOrInside: project.appending(path: "Other"), of: repository))
    }

    @Test func aRepositoryWithNothingAddedTracksNothing() async throws {
        let directory = try TemporaryDirectory()
        let project = try makeProject(in: directory)
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        try await git.run("init", "-q", in: project)

        let repository = try #require(GitIndex.repository(containing: project))
        let index = try #require(GitIndex.read(repository))
        #expect(!index.tracksSomething(atOrInside: project.appending(path: "Pods"), of: repository))
    }

    @Test func aFolderOnlyNamedLikeATrackedOneIsNotTracked() async throws {
        let directory = try TemporaryDirectory()
        let project = try makeProject(in: directory)
        _ = try directory.file("App/PodsArchive/Foo.m")
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        try await git.run("init", "-q", in: project)
        try await git.run("add", "PodsArchive", in: project)

        let repository = try #require(GitIndex.repository(containing: project))
        let index = try #require(GitIndex.read(repository))
        #expect(index.tracksSomething(atOrInside: project.appending(path: "PodsArchive"), of: repository))
        #expect(!index.tracksSomething(atOrInside: project.appending(path: "Pods"), of: repository))
    }

    @Test(.permissionsHold) func anIndexItCannotReadIsNotKnown() async throws {
        let directory = try TemporaryDirectory()
        let project = try makeProject(in: directory)
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        try await git.run("init", "-q", in: project)
        try await git.run("add", "Pods", in: project)
        let index = project.appending(path: ".git/index")
        try directory.setPermissions(0, of: index)
        defer { try? directory.setPermissions(0o644, of: index) }

        let repository = try #require(GitIndex.repository(containing: project))
        #expect(GitIndex.read(repository) == nil)
    }

    @Test func neverLooksPastTheDiskItStartedOn() async throws {
        let directory = try TemporaryDirectory()
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        try await git.run("init", "-q", in: directory.url)
        let disk = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk"))
        let project = disk.url.appending(path: "App", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project.appending(path: "Pods"), withIntermediateDirectories: true)

        #expect(GitIndex.repository(containing: directory.url) != nil)
        #expect(GitIndex.repository(containing: project) == nil)
    }

    private func makeProject(in directory: borrowing TemporaryDirectory) throws -> URL {
        _ = try directory.file("App/Podfile")
        _ = try directory.file("App/Pods/Foo/Foo.m")
        _ = try directory.file("App/src/App.swift")
        _ = try directory.file("App/Other/notes.txt")
        return directory.url.appending(path: "App", directoryHint: .isDirectory)
    }
}
