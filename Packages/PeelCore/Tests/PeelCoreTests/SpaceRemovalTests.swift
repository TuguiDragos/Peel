import Foundation
@testable import PeelCore
import Synchronization
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

    /// An area only its own app or tool should empty, such as a virtual machine's disks, is never planned for the
    /// Trash, whoever asks.
    @Test func plansNothingInAnAreaItsOwnToolEmpties() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Containers/org.example.vm/Data/vms/0/disk.img", bytes: 64)
        let machines = SpaceItem(
            id: "virtual-machines",
            category: .virtualMachines,
            urls: [directory.url.appending(path: "home/Library/Containers/org.example.vm/Data/vms", directoryHint: .isDirectory)],
            size: 64,
            handling: .readOnly
        )

        let plan = await SpaceRemoval.plan(for: machines, environment: environment(directory))
        let removable = await SpaceRemoval.removable(in: machines, environment: environment(directory))

        #expect(plan.removable.isEmpty)
        #expect(removable.isEmpty)
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

    @Test func measuresWhatItLeavesToDeveloper() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.2/caches/index.db", bytes: 8192)
        try directory.file("home/Library/Caches/com.gone.app/old.db")

        let plan = await SpaceRemoval.plan(for: item(directory), environment: environment(directory))
        let sizes = await SpaceRemoval.sizesLeftToDeveloper(in: plan)

        let jetBrains = try #require(plan.leftToDeveloper.first)
        #expect(plan.developerSizes == nil)
        #expect(sizes[jetBrains] ?? 0 >= 8192)
        #expect(Set(sizes.keys) == Set(plan.leftToDeveloper))
    }

    @Test func offersTheRestOfAVendorsFolderThatHoldsAToolsOwn() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/Google/Chrome/Default/Cache/Cache_Data/data_0")
        try directory.file("home/Library/Caches/Google/AndroidStudio2026.1.4/caches/index.db")
        try directory.file("home/Library/Caches/Google/AndroidStudio2026.1.4/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/Google/AndroidStudio2025.3.1/caches/index.db")
        try directory.file("home/Library/Caches/Coursier/jvm/adoptium@17/bin/java")
        try directory.file("home/Library/Logs/Google/AndroidStudio2026.1.4/idea.log")
        try directory.file("home/Library/Logs/Google/GoogleUpdater/updater.log")
        let logs = SpaceItem(
            id: "logs",
            category: .library,
            urls: [directory.url.appending(path: "home/Library/Logs", directoryHint: .isDirectory)],
            size: 0,
            handling: .trash
        )
        let named = { (urls: [URL]) in
            urls.map { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" }.sorted()
        }

        let caches = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), running: [:])
        let logged = await SpaceRemoval.plan(for: logs, environment: environment(directory), running: [:])

        #expect(named(caches.removable) == ["Google/Chrome"])
        #expect(
            named(caches.leftToDeveloper)
                == ["Caches/Coursier", "Google/AndroidStudio2025.3.1", "Google/AndroidStudio2026.1.4"]
        )
        #expect(caches.refused.isEmpty)
        #expect(named(logged.removable) == ["Google/GoogleUpdater"])
        #expect(named(logged.leftToDeveloper) == ["Google/AndroidStudio2026.1.4"])
    }

    @Test func neverGoesThroughALinkIntoAnotherFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Projects/Site/index.html")
        try directory.directory("home/Library/Caches")
        let google = directory.url.appending(path: "home/Library/Caches/Google")
        let projects = directory.url.appending(path: "home/Projects")
        try FileManager.default.createSymbolicLink(at: google, withDestinationURL: projects)

        let plan = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), running: [:])

        #expect(plan.removable.isEmpty, "offered \(plan.removable.map(\.path))")
        #expect(plan.leftToDeveloper.map(\.lastPathComponent) == ["Google"])
    }

    @Test func neverSelectsACacheMacOSKeepsForItself() async throws {
        let directory = try TemporaryDirectory()
        for name in ["com.apple.Spotlight", "CloudKit", "familycircled", "GameStoreKit", "org.example.notes", "com.gone.app"] {
            try directory.file("home/Library/Caches/\(name)/data.db")
        }
        try directory.file("home/Library/Logs/com.apple.example/run.log")
        let logs = SpaceItem(
            id: "logs",
            category: .library,
            urls: [directory.url.appending(path: "home/Library/Logs", directoryHint: .isDirectory)],
            size: 0,
            handling: .trash
        )
        let names = { (urls: [URL]) in urls.map(\.lastPathComponent).sorted() }

        let caches = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), running: [:])
        let logged = await SpaceRemoval.plan(for: logs, environment: environment(directory), running: [:])

        let all = ["CloudKit", "GameStoreKit", "com.apple.Spotlight", "com.gone.app", "familycircled", "org.example.notes"]
        #expect(names(caches.removable) == all)
        #expect(names(Array(caches.suggested)) == ["com.gone.app", "org.example.notes"])
        let keptByMacOS = caches.heldBack.filter { $0.value == .keptByMacOS }.map(\.key)
        #expect(names(keptByMacOS) == ["CloudKit", "GameStoreKit", "com.apple.Spotlight", "familycircled"])
        #expect(names(Array(logged.suggested)) == ["com.apple.example"])
    }

    /// macOS's own services keep theirs, Developer's go to Developer, and the folder itself is never offered.
    @Test func plansTheFolderMacOSGivesTheAccountForCachesWithoutMacOSsOwn() async throws {
        let directory = try TemporaryDirectory()
        for name in ["com.apple.dock.iconcache", "assessmentagent", "AudioComponentRegistrar", "org.example.editor"] {
            try directory.file("C/\(name)/data.db")
        }
        try directory.file("C/clang/ModuleCache/index.pcm")
        let userCache = directory.url.appending(path: "C", directoryHint: .isDirectory)
        var environment = environment(directory)
        environment.userCacheDirectory = userCache
        let caches = SpaceItem(
            id: "user-caches", category: .library, urls: [userCache], size: 0, handling: .trash, leavesMacOSsOwn: true
        )

        let plan = await SpaceRemoval.plan(for: caches, environment: environment, running: [:])

        #expect(plan.removable.map(\.lastPathComponent) == ["org.example.editor"])
        #expect(plan.suggested == Set(plan.removable))
        #expect(plan.leftToDeveloper.map(\.lastPathComponent) == ["clang"])
        #expect(RemovalGuard(environment: environment).refusal(of: userCache) == .staysItself)
    }

    /// In the caches every account shares, what macOS keeps is left out of the plan altogether: its services run
    /// as other accounts, whose open files Peel cannot see. What only an administrator can move goes through the
    /// helper.
    @Test func leavesMacOSsOwnOutOfTheCachesEveryAccountShares() async throws {
        let directory = try TemporaryDirectory()
        for name in ["com.apple.iconservices.store", "ColorSync", "Desktop Pictures", "org.example.updater"] {
            try directory.file("root/Library/Caches/\(name)/data.bin")
        }
        let shared = SpaceItem(
            id: "system-caches",
            category: .library,
            urls: [directory.url.appending(path: "root/Library/Caches", directoryHint: .isDirectory)],
            size: 0,
            handling: .trash,
            leavesMacOSsOwn: true
        )

        let plan = await SpaceRemoval.plan(for: shared, environment: environment(directory), running: [:])

        #expect(plan.removable.map(\.lastPathComponent) == ["org.example.updater"])
        #expect(plan.needsTheHelper.isEmpty, "a folder the person owns moves without the helper")
    }

    @Test func offersTheLogsAndReportsEveryAccountSharesButMacOSsOwn() async throws {
        let directory = try TemporaryDirectory()
        for path in [
            "org.example.tool/run.log", "WindowServer/session.log", "MCXTools.log",
            "DiagnosticReports/Example_2026-09-28.ips", "DiagnosticReports/Retired/panic-full.ips",
        ] {
            try directory.file("root/Library/Logs/\(path)")
        }
        let logs = directory.url.appending(path: "root/Library/Logs", directoryHint: .isDirectory)
        let reports = logs.appending(path: "DiagnosticReports", directoryHint: .isDirectory)
        let shared = SpaceItem(
            id: "system-logs",
            category: .library,
            urls: [logs, reports],
            size: 0,
            handling: .trash,
            leavesMacOSsOwn: true,
            onlyFilesIn: [reports]
        )

        let plan = await SpaceRemoval.plan(for: shared, environment: environment(directory), running: [:])

        #expect(plan.removable.map(\.lastPathComponent).sorted() == ["Example_2026-09-28.ips", "org.example.tool"])
        #expect(plan.refused.isEmpty)
    }

    @Test(.permissionsHold) func whatOnlyAnAdministratorCanMoveGoesThroughTheHelper() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Library/Caches/org.example.updater/data.bin")
        try directory.setPermissions(0o555, of: "root/Library/Caches")
        defer { try? directory.setPermissions(0o755, of: "root/Library/Caches") }
        let shared = SpaceItem(
            id: "system-caches",
            category: .library,
            urls: [directory.url.appending(path: "root/Library/Caches", directoryHint: .isDirectory)],
            size: 0,
            handling: .trash,
            leavesMacOSsOwn: true
        )

        let plan = await SpaceRemoval.plan(for: shared, environment: environment(directory), running: [:])

        #expect(plan.needsTheHelper.map(\.lastPathComponent) == ["org.example.updater"])
        #expect(plan.heldBack.isEmpty, "the helper serves the caches every account shares")
    }

    @Test(.permissionsHold) func whatOnlyAnAdministratorCanMoveWaitsForTheHelperToBeSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Library/Caches/org.example.updater/data.bin")
        try directory.setPermissions(0o555, of: "root/Library/Caches")
        defer { try? directory.setPermissions(0o755, of: "root/Library/Caches") }
        let shared = SpaceItem(
            id: "system-caches",
            category: .library,
            urls: [directory.url.appending(path: "root/Library/Caches", directoryHint: .isDirectory)],
            size: 0,
            handling: .trash,
            leavesMacOSsOwn: true
        )

        let plan = await SpaceRemoval.plan(for: shared, environment: environment(directory), running: [:])
        let updater = try #require(plan.removable.first)

        #expect(plan.needsTheHelper == [updater])
        #expect(plan.selection(keeping: [updater], canUseHelper: false).isEmpty)
        #expect(plan.selection(keeping: [updater], canUseHelper: true) == [updater])
        #expect(plan.selectableRows(canUseHelper: false).recommended.isEmpty)
        #expect(plan.selectableRows(canUseHelper: true).recommended == [updater])
    }

    @Test func emptiesAContainersCachesUnlessItsAppIsOpenOrApples() async throws {
        let directory = try TemporaryDirectory()
        let containers = "home/Library/Containers"
        for container in ["org.example.chat", "org.example.notes", "com.apple.Safari"] {
            try directory.file("\(containers)/\(container)/Data/Library/Caches/Cache.db", bytes: 4_096)
        }
        let item = SpaceItem(
            id: "container-caches",
            category: .library,
            urls: ["org.example.chat", "org.example.notes", "com.apple.Safari"].map {
                directory.url.appending(path: "\(containers)/\($0)/Data/Library/Caches", directoryHint: .isDirectory)
            },
            size: 0,
            handling: .trash
        )
        let notes = URL(filePath: "/Applications/Notes Example.app")
        let running = [RunningCopies.Process(identifier: 1, bundleIdentifier: "org.example.notes", bundleURL: notes)]
        let owner = { (url: URL) in url.pathComponents.dropLast(4).last ?? "" }

        let names = SpaceRemoval.namesOfRunningApps(running)
        let plan = await SpaceRemoval.plan(for: item, environment: environment(directory), running: names)

        #expect(plan.removable.map(owner).sorted() == ["com.apple.Safari", "org.example.chat"])
        #expect(plan.suggested.map(owner) == ["org.example.chat"])
        #expect(plan.heldBack.filter { $0.value == .keptByMacOS }.map { owner($0.key) } == ["com.apple.Safari"])
        #expect(plan.inUse.map { owner($0.url) } == ["org.example.notes"])
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

    @Test func leavesAGroupContainersCachesAloneWhileAnAppSharingItIsOpen() async throws {
        let directory = try TemporaryDirectory()
        let groups = "home/Library/Group Containers"
        try directory.file("\(groups)/ABCDE12345.org.example.shared/Library/Caches/blob/data", bytes: 4_096)
        try directory.file("\(groups)/ABCDE12345.org.example.other/Library/Caches/blob/data", bytes: 4_096)
        let item = SpaceItem(
            id: "container-caches",
            category: .library,
            urls: ["shared", "other"].map { name in
                let caches = "\(groups)/ABCDE12345.org.example.\(name)/Library/Caches"
                return directory.url.appending(path: caches, directoryHint: .isDirectory)
            },
            size: 8_192,
            handling: .trash
        )

        let plan = await SpaceRemoval.plan(
            for: item, environment: environment(directory),
            running: [Naming.normalized("ABCDE12345.org.example.shared"): "Chat Example"]
        )

        let group = { (url: URL) in url.pathComponents.dropLast(3).last ?? "" }
        #expect(plan.removable.map(group) == ["ABCDE12345.org.example.other"])
        #expect(plan.appsToQuit == ["Chat Example"])
    }

    @Test func anOpenAppAnswersToTheGroupsItsSignatureClaims() {
        let notes = RunningCopies.Process(
            identifier: 1, bundleIdentifier: "com.apple.Notes",
            bundleURL: URL(filePath: "/System/Applications/Notes.app")
        )

        let names = SpaceRemoval.namesOfRunningApps([notes])

        #expect(names[Naming.normalized("group.com.apple.notes")] != nil)
    }

    @Test func leavesEveryAttachmentMailKeptForThePersonToChoose() async throws {
        let directory = try TemporaryDirectory()
        let downloads = [
            "home/Library/Mail Downloads", "home/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
        ]
        try directory.file("\(downloads[0])/0C6E/Invoice.pdf", bytes: 4_096)
        try directory.file("\(downloads[1])/5A1F/Plan.pages", bytes: 4_096)
        let item = SpaceItem(
            id: "mail-downloads",
            category: .library,
            urls: downloads.map { directory.url.appending(path: $0, directoryHint: .isDirectory) },
            size: 8_192,
            handling: .trash,
            heldBack: .openedFromMail
        )
        let mail = RunningCopies.Process(
            identifier: 1, bundleIdentifier: "com.apple.mail", bundleURL: URL(filePath: "/System/Applications/Mail.app")
        )

        let closed = await SpaceRemoval.plan(for: item, environment: environment(directory), running: [:])
        let open = await SpaceRemoval.plan(
            for: item, environment: environment(directory), running: SpaceRemoval.namesOfRunningApps([mail])
        )

        #expect(closed.removable.map(\.lastPathComponent).sorted() == ["0C6E", "5A1F"])
        #expect(closed.suggested.isEmpty)
        #expect(Set(closed.heldBack.values) == [.openedFromMail])
        #expect(closed.heldBack.count == 2)
        #expect(open.removable.map(\.lastPathComponent) == ["0C6E"])
        #expect(open.appsToQuit == ["Mail"])
    }

    /// A move asks again just before it moves anything, since an app opened since the plan may be writing to some
    /// of these folders. It needs to know what may go, not how big it is, and it finds what a plan would.
    @Test func theMovesCheckFindsWhatAPlanWould() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.spotify.client/audio.db")
        try directory.file("home/Library/Caches/com.gone.app/old.db")
        try directory.file("home/Library/Caches/Coursier/v1/https/repo.jar")
        let running = ["comspotifyclient": "Spotify"]

        let plan = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), running: running)
        let removable = await SpaceRemoval.removable(
            in: item(directory),
            environment: environment(directory),
            running: running
        )

        #expect(removable.map(\.lastPathComponent) == ["com.gone.app"])
        #expect(removable == plan.removable)
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

        let plan = await SpaceRemoval.plan(
            for: item(directory),
            environment: environment(directory),
            running: SpaceRemoval.namesOfRunningApps(running)
        )

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

    @Test func saysWhyItLeavesAloneWhatTheGuardRefuses() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/org.example.Editor/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/org.example.Kept/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.2/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.2/caches/index.db")
        try directory.file("home/Library/Caches/com.gone.app/old.db")
        let kept = directory.url.appending(path: "home/Library/Caches/org.example.Kept", directoryHint: .isDirectory)

        let plan = await SpaceRemoval.plan(
            for: item(directory), environment: environment(directory), exclusions: Exclusions(paths: [kept]),
            running: [:]
        )

        #expect(plan.removable.map(\.lastPathComponent) == ["com.gone.app"])
        #expect(plan.leftToDeveloper.map(\.lastPathComponent) == ["JetBrains"])
        let refused = plan.refused.map { "\($0.key.lastPathComponent): \($0.value)" }
        #expect(refused == ["org.example.Editor: holdsWorkKeptInACache"])
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

    @Test func leavesAnExcludedAppsOwnFolderAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/org.example.Notes/keep.db")
        try directory.file("home/Library/Caches/com.gone.app/old.db")

        let plan = await SpaceRemoval.plan(
            for: item(directory),
            environment: environment(directory),
            exclusions: Exclusions(bundleIdentifiers: ["org.example.Notes"]),
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

    /// What may exist nowhere else is never selected for the person: a child with a wallet or a repository inside
    /// is left for them to choose, with its reason.
    @Test func aChildHoldingAWalletOrARepositoryIsLeftToChoose() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.coin.app/wallets/default", bytes: 100)
        try directory.file("home/Library/Caches/com.tool.app/mirror/.git/HEAD", bytes: 100)
        try directory.file("home/Library/Caches/com.gone.app/old.db", bytes: 100)

        let plan = await SpaceRemoval.plan(for: item(directory), environment: environment(directory), running: [:])

        let reasons = plan.removable.map { "\($0.lastPathComponent): \(plan.heldBack[$0].map(\.rawValue) ?? "none")" }.sorted()
        #expect(reasons == ["com.coin.app: holdsAWallet", "com.gone.app: none", "com.tool.app: holdsRepository"])
        #expect(plan.suggested.map(\.lastPathComponent) == ["com.gone.app"])
    }

    /// Each removed item is recorded with its size, so History shows what a cleanup freed. A child that did not
    /// answer in time still goes, and only its size is unknown.
    @Test func aChildThatDidNotAnswerStillGoesAndHasNoSize() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.slow.app/blob", bytes: 40_000)
        try directory.file("home/Library/Caches/com.gone.app/small.db", bytes: 4_000)

        let plan = await SpaceRemoval.plan(
            for: item(directory),
            environment: environment(directory),
            exclusions: .none,
            running: [:]
        ) { url in
            url.lastPathComponent == "com.slow.app" ? nil : await FileSize.contents(of: url)
        }

        #expect(Set(plan.removable.map(\.lastPathComponent)) == ["com.slow.app", "com.gone.app"])
        #expect(plan.sizes.keys.map(\.lastPathComponent) == ["com.gone.app"])
        #expect(plan.heldBack.map { "\($0.key.lastPathComponent): \($0.value.rawValue)" } == ["com.slow.app: notMeasured"])
    }

    @Test func measuresAFewChildrenAtATime() async throws {
        let directory = try TemporaryDirectory()
        for index in 0..<8 {
            try directory.file("home/Library/Caches/org.example.app\(index)/blob", bytes: 4_000)
        }
        let running = Mutex((now: 0, most: 0))

        let plan = await SpaceRemoval.plan(
            for: item(directory),
            environment: environment(directory),
            exclusions: .none,
            running: [:]
        ) { _ in
            running.withLock { $0.now += 1; $0.most = max($0.most, $0.now) }
            try? await Task.sleep(for: .milliseconds(500))
            running.withLock { $0.now -= 1 }
            return FolderContents(size: 4_000, holdsRepository: false)
        }

        #expect(plan.sizes.count == 8)
        #expect(running.withLock { $0.most } == LeftoverScanner.concurrentMeasurements)
    }

    /// An area's plan is made again when the disk changes: what the person chose stays chosen while it is still
    /// there, and nothing is selected for them, in the first plan or among the children new to the area.
    @Test func aPlanMadeAgainKeepsWhatThePersonChose() {
        let caches = URL(filePath: "/Users/x/Library/Caches", directoryHint: .isDirectory)
        let (kept, deselected, chosenByHand, unmeasured, new, gone, noLongerMeasured) = (
            caches.appending(path: "com.a"), caches.appending(path: "com.b"), caches.appending(path: "com.c"),
            caches.appending(path: "com.d"), caches.appending(path: "com.e"), caches.appending(path: "com.f"),
            caches.appending(path: "com.g")
        )
        let first = SpaceRemoval.Plan(
            removable: [kept, deselected, chosenByHand, unmeasured, gone, noLongerMeasured],
            inUse: [],
            leftToDeveloper: [],
            sizes: [kept: 1, deselected: 2, gone: 5, noLongerMeasured: 7]
        )
        #expect(first.selection(keeping: [], canUseHelper: true).isEmpty)

        let again = SpaceRemoval.Plan(
            removable: [kept, deselected, chosenByHand, unmeasured, new, noLongerMeasured],
            inUse: [],
            leftToDeveloper: [],
            sizes: [kept: 1, deselected: 2, chosenByHand: 3, unmeasured: 4, new: 6]
        )
        let selected: Set = [kept, chosenByHand, gone, noLongerMeasured]
        #expect(again.selection(keeping: selected, canUseHelper: true) == [kept, chosenByHand, noLongerMeasured])
    }

    @Test func anAreaSelectsNothingUntilThePersonDoes() {
        let caches = URL(filePath: "/Users/x/Library/Caches", directoryHint: .isDirectory)
        let (measured, chosen) = (caches.appending(path: "com.a"), caches.appending(path: "com.b"))
        let plan = SpaceRemoval.Plan(
            removable: [measured, chosen], inUse: [], leftToDeveloper: [], sizes: [measured: 1, chosen: 2]
        )
        #expect(plan.selection(keeping: [], canUseHelper: true).isEmpty)
        #expect(plan.selection(keeping: [chosen], canUseHelper: true) == [chosen])
        #expect(Set(plan.selectableRows(canUseHelper: true).recommended) == [measured, chosen])
    }

    @Test func aChildThatWaitsForTheHelperCanBeSelectedOnlyOnceTheHelperCanAct() {
        let caches = URL(filePath: "/Library/Caches", directoryHint: .isDirectory)
        let vendor = caches.appending(path: "org.example.Vendor")
        let system = caches.appending(path: "org.example.System")
        let plan = SpaceRemoval.Plan(
            removable: [vendor, system], inUse: [], leftToDeveloper: [], sizes: [vendor: 1, system: 2],
            needsTheHelper: [system]
        )
        #expect(plan.selection(keeping: [vendor, system], canUseHelper: false) == [vendor])
        #expect(plan.selection(keeping: [vendor, system], canUseHelper: true) == [vendor, system])
    }
}
