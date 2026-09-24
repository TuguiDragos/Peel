import Foundation
@testable import PeelCore
import Testing

/// Space empties a folder by listing what is inside it. Each item listed still goes through the guard and the
/// exclusions, and an app that is open keeps what it is using.
struct SpaceRemovalTests {
    private func item(_ directory: borrowing TemporaryDirectory) -> SpaceItem {
        SpaceItem(
            id: "caches",
            category: .library,
            urls: [directory.url.appending(path: "home/Library/Caches", directoryHint: .isDirectory)],
            size: 0,
            handling: .trash
        )
    }

    private func environment(_ directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
    }

    /// Space moves each folder inside Caches whole, but Coursier's folder holds the JVMs that `JAVA_HOME` points
    /// at, and Poetry's holds its virtual environments. Only Developer knows which part of such a folder is a cache.
    @Test func leavesToDeveloperEveryFolderDeveloperListsSomethingInside() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/Coursier/jvm/adoptium@17/bin/java")
        try directory.file("home/Library/Caches/Coursier/v1/https/repo.jar")
        try directory.file("home/Library/Caches/pypoetry/virtualenvs/project-py3.12/pyvenv.cfg")
        try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.2/caches/index.db")
        try directory.file("home/Library/Caches/com.gone.app/old.db")
        let logs = SpaceItem(
            id: "logs",
            category: .library,
            urls: [directory.url.appending(path: "home/Library/Logs", directoryHint: .isDirectory)],
            size: 0,
            handling: .trash
        )
        try directory.file("home/Library/Logs/JetBrains/idea.log")
        try directory.file("home/Library/Logs/com.gone.app/run.log")

        let caches = await SpaceRemoval.plan(for: item(directory), environment: environment(directory))
        let logged = await SpaceRemoval.plan(for: logs, environment: environment(directory))

        #expect(caches.removable.map(\.lastPathComponent) == ["com.gone.app"])
        #expect(caches.leftToDeveloper.map(\.lastPathComponent).sorted() == ["Coursier", "JetBrains", "pypoetry"])
        #expect(logged.removable.map(\.lastPathComponent) == ["com.gone.app"])
        #expect(logged.leftToDeveloper.map(\.lastPathComponent) == ["JetBrains"])
    }

    @Test func leavesAloneWhatAnOpenAppIsStillUsing() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.spotify.client/audio.db")
        try directory.file("home/Library/Caches/com.gone.app/old.db")

        let plan = await SpaceRemoval.plan(
            for: item(directory),
            environment: environment(directory),
            running: ["comspotifyclient": "Spotify", "client": "Spotify"]
        )

        #expect(plan.removable.map(\.lastPathComponent) == ["com.gone.app"])
        #expect(plan.appsToQuit == ["Spotify"])
    }

    /// Many cache and log folders are named after the app rather than its bundle identifier, such as `Firefox`,
    /// `Mozilla`, `JetBrains` and `Zed`. Emptying one while its app writes to it is the risk here.
    @Test func leavesAloneAFolderNamedAfterTheOpenAppRatherThanItsIdentifier() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/Firefox/Profiles/cache.db")
        try directory.file("home/Library/Caches/Zed/data.db")
        try directory.file("home/Library/Caches/com.gone.app/old.db")
        let running = [
            RunningCopies.Process(identifier: 1, bundleIdentifier: "org.mozilla.firefox", bundleURL: URL(filePath: "/Applications/Firefox.app")),
            RunningCopies.Process(identifier: 2, bundleIdentifier: "dev.zed.Zed", bundleURL: URL(filePath: "/Applications/Zed.app")),
        ]

        let plan = await SpaceRemoval.plan(
            for: item(directory),
            environment: environment(directory),
            running: SpaceRemoval.namesOfRunningApps(running)
        )

        #expect(plan.removable.map(\.lastPathComponent) == ["com.gone.app"])
        #expect(plan.appsToQuit == ["Firefox", "Zed"])
    }

    /// One open app can write to several folders, by its name and by its identifier. The note names it once.
    @Test func namesAnOpenAppOnceWhateverItsFoldersAreCalled() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/Zed/data.db")
        try directory.file("home/Library/Caches/dev.zed.Zed/index.db")
        let running = [RunningCopies.Process(identifier: 2, bundleIdentifier: "dev.zed.Zed", bundleURL: URL(filePath: "/Applications/Zed.app"))]

        let plan = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), running: SpaceRemoval.namesOfRunningApps(running))

        #expect(plan.appsToQuit == ["Zed"], "the note would read \(plan.appsToQuit.formatted(.list(type: .and)))")
    }

    /// A cache folder is not always only a cache. A JetBrains IDE and Android Studio keep `LocalHistory` (the
    /// edits they recorded, which are in no repository) beside their caches, under a folder named after the
    /// vendor and not after the app, so the open app check never sees it. Deno keeps `location_data` there.
    @Test func leavesACacheFolderThatHoldsSomebodysWork() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/Google/AndroidStudio2026.1.4/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/Google/AndroidStudio2026.1.4/caches/index.db")
        try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.2/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/deno/location_data/abc/kv.sqlite3")
        try directory.file("home/Library/Caches/com.gone.app/old.db")

        let plan = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), running: [:])

        #expect(plan.removable.map(\.lastPathComponent) == ["com.gone.app"])
    }

    @Test func neverOffersTheFolderItself() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.gone.app/old.db")

        let plan = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), running: [:])

        #expect(!plan.removable.contains { $0.lastPathComponent == "Caches" })
    }

    @Test func appliesTheUsersExclusions() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.keep.app/keep.db")
        try directory.file("home/Library/Caches/com.gone.app/old.db")
        let kept = directory.url.appending(path: "home/Library/Caches/com.keep.app", directoryHint: .isDirectory)

        let plan = await SpaceRemoval.plan(
            for: item(directory),
            environment: environment(directory),
            exclusions: Exclusions(paths: [kept]),
            running: [:]
        )

        #expect(plan.removable.map(\.lastPathComponent) == ["com.gone.app"])
    }

    /// The figure on the screen is what emptying will free, not what the folder holds.
    @Test func sizeCountsOnlyWhatWillActuallyGo() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.open.app/big.db", bytes: 40_000)
        try directory.file("home/Library/Caches/com.gone.app/small.db", bytes: 4_000)

        let plan = await SpaceRemoval.plan(
            for: item(directory),
            environment: environment(directory),
            running: ["comopenapp": "Open"]
        )

        #expect(plan.sizes.keys.map(\.lastPathComponent) == ["com.gone.app"])
        #expect(try #require(plan.sizes.values.first) >= 4_000)
    }

    /// Each removed item is recorded with its size, so History shows what a cleanup freed. A child that did not
    /// answer in time still goes, and only its size is unknown.
    @Test func aChildThatDidNotAnswerStillGoesAndHasNoSize() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.slow.app/blob", bytes: 40_000)
        try directory.file("home/Library/Caches/com.gone.app/small.db", bytes: 4_000)

        let plan = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), exclusions: .none, running: [:]) { url in
            url.lastPathComponent == "com.slow.app" ? nil : await FileSize.allocatedSize(of: url, within: FileSize.budget)
        }

        #expect(Set(plan.removable.map(\.lastPathComponent)) == ["com.slow.app", "com.gone.app"])
        #expect(plan.sizes.keys.map(\.lastPathComponent) == ["com.gone.app"])
    }
}
