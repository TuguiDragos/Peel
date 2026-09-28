import Foundation
@testable import PeelCore
import Testing

struct SpaceInventoryTests {
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        let paths = SpaceInventory.definitions.flatMap(\.paths)
        for path in paths {
            try directory.directory(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        }
        let unanswered = Unanswered()

        let stop = try await unanswered.stop {
            _ = await SpaceInventory.scan(home: directory.url, root: directory.url, minimumSize: 1, measure: unanswered.measure)
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < SpaceInventory.definitions.count)
        #expect(stop.askedAfter == 0)
    }

    @Test func reportsOnlyWhatIsBigEnough() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Logs/big.log", bytes: 400_000)
        try directory.file(".colima/machine/disk.img", bytes: 16)

        let report = await SpaceInventory.scan(home: directory.url, root: directory.url, minimumSize: 100_000, measure: FileSize.measure)
        #expect(report.items.map(\.id) == ["logs"])
        #expect(report.items.first?.handling == .trash)

        let everything = await SpaceInventory.scan(home: directory.url, root: directory.url, minimumSize: 1, measure: FileSize.measure)
        #expect(Set(everything.items.map(\.id)) == ["logs", "colima"])
    }

    /// The folders Space exists to show are the ones most likely to run out of time. Such a folder stays in the
    /// report, listed first, with an unknown size.
    @Test func keepsAFolderThatDidNotAnswerInTime() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Logs/big.log", bytes: 400_000)
        try directory.file("Library/Caches/com.example.app/blob", bytes: 400_000)

        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        let report = await SpaceInventory.scan(home: directory.url, root: root, minimumSize: 100_000) { url in
            url.lastPathComponent == "Caches" ? nil : await FileSize.reclaimableSize(of: url, within: FileSize.budget)
        }

        #expect(report.items.map(\.id) == ["caches", "logs"])
        #expect(report.items.first?.size == nil)
        #expect(try #require(report.items.last?.size) >= 400_000)
    }

    /// Without Full Disk Access some areas are refused, and a refused one is kept like one that ran out of time.
    @Test(.permissionsHold) func keepsAFolderItCannotOpen() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Logs/big.log", bytes: 400_000)
        try directory.setPermissions(0, of: "Library/Logs")
        defer { try? directory.setPermissions(0o755, of: "Library/Logs") }

        let report = await SpaceInventory.scan(home: directory.url, root: directory.url, minimumSize: 100_000, measure: FileSize.measure)
        #expect(report.items.map(\.id) == ["logs"])
        #expect(report.items.first?.size == nil)
        #expect(!report.needsFullDiskAccess, "ordinary permissions were read as a refusal Full Disk Access would lift")
    }

    @Test func leavesWhatOthersOwnToThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".colima/machine/disk.img", bytes: 4096)

        let report = await SpaceInventory.scan(home: directory.url, root: directory.url, minimumSize: 1, measure: FileSize.measure)
        let machines = try #require(report.items.first { $0.id == "colima" })
        #expect(machines.isReadOnly)
        #expect(machines.category == .virtualMachines)
    }

    /// macOS 26 keeps the downloaded aerials per user, not in the shared folder macOS 14 and 15 used.
    @Test func findsTheAerialWallpapersWhereMacOS26KeepsThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Application Support/com.apple.wallpaper/aerials/videos/a.mov", bytes: 400_000)

        let report = await SpaceInventory.scan(home: directory.url, root: directory.url, minimumSize: 100_000, measure: FileSize.measure)
        #expect(report.items.map(\.id) == ["wallpapers"])
    }

    /// The simulator caches belong to Developer, which selects them, so Space leaves them out. The runtimes, the
    /// larger part, sit outside the home folder and are counted here.
    @Test func countsTheSimulatorRuntimesAndLeavesTheCachesToDeveloper() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Developer/CoreSimulator/Devices/one/data.bin", bytes: 400_000)
        try directory.file("Library/Developer/CoreSimulator/Caches/dyld/shared.bin", bytes: 400_000)
        try directory.file("Library/Developer/CoreSimulator/Images/runtime.dmg", bytes: 400_000)

        let report = await SpaceInventory.scan(home: directory.url, root: directory.url, minimumSize: 100_000, measure: FileSize.measure)
        let simulators = try #require(report.items.first { $0.id == "simulators" })
        let paths = simulators.urls.map { $0.lastPathComponent }

        #expect(paths.contains("Devices"))
        #expect(paths.contains("Images"))
        #expect(!paths.contains("Caches"), "the caches Developer selects are counted here as well")
    }

    @Test func findsTheCachesAndLogsInEveryAppsContainer() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Containers/org.example.chat/Data/Library/Caches/blob", bytes: 8_000)
        try directory.file("Library/Containers/org.example.chat/Data/Library/Logs/run.log", bytes: 8_000)
        try directory.file("Library/Containers/org.example.notes/Data/Library/Caches/blob", bytes: 8_000)
        try directory.directory("Library/Containers/org.example.empty/Data/Documents")
        try directory.directory("Elsewhere/Data/Library/Caches")
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "Library/Containers/org.example.link"),
            withDestinationURL: directory.url.appending(path: "Elsewhere")
        )

        let report = await SpaceInventory.scan(
            home: directory.url, root: directory.url, minimumSize: 1, measure: FileSize.measure
        )

        let folders = { (id: String) in
            report.items.first { $0.id == id }?.urls.map { $0.pathComponents.suffix(4).joined(separator: "/") } ?? []
        }
        let caches = ["org.example.chat/Data/Library/Caches", "org.example.notes/Data/Library/Caches"]
        #expect(folders("container-caches") == caches)
        #expect(folders("logs").contains("org.example.chat/Data/Library/Logs"))
    }

    @Test func findsTheCopiesMailKeepsOfTheAttachmentsYouOpen() async throws {
        let directory = try TemporaryDirectory()
        let container = "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        try directory.file("Library/Mail Downloads/0C6E/Invoice.pdf", bytes: 8_000)
        try directory.file("\(container)/5A1F/Plan.pages", bytes: 8_000)

        let report = await SpaceInventory.scan(
            home: directory.url, root: directory.url, minimumSize: 1, measure: FileSize.measure
        )

        let attachments = try #require(report.items.first { $0.id == "mail-downloads" })
        #expect(attachments.urls == [
            directory.url.appending(path: "Library/Mail Downloads", directoryHint: .isDirectory),
            directory.url.appending(path: container, directoryHint: .isDirectory),
        ])
        #expect(attachments.handling == .trash)
        #expect(attachments.heldBack == .openedFromMail)
    }

    @Test func findsTheCachesOfEveryGroupContainerButApplesAndTheTemporaryFilesOfEveryContainer() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Group Containers/ABCDE12345.org.example.shared/Library/Caches/blob", bytes: 8_000)
        try directory.file("Library/Group Containers/group.com.apple.notes/Library/Caches/blob", bytes: 8_000)
        try directory.file("Library/Containers/org.example.chat/Data/tmp/upload.part", bytes: 8_000)

        let report = await SpaceInventory.scan(
            home: directory.url, root: directory.url, minimumSize: 1, measure: FileSize.measure
        )

        let folders = report.items.first { $0.id == "container-caches" }?.urls
            .map { $0.pathComponents.suffix(3).joined(separator: "/") } ?? []
        #expect(Set(folders) == ["ABCDE12345.org.example.shared/Library/Caches", "org.example.chat/Data/tmp"])
    }

    @Test func findsTheCacheBattleNetKeepsForEveryAccount() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Users/Shared/Blizzard/Battle.net/Cache/data.bin", bytes: 8_000)

        let report = await SpaceInventory.scan(
            home: directory.url.appending(path: "home", directoryHint: .isDirectory),
            root: directory.url.appending(path: "root", directoryHint: .isDirectory),
            minimumSize: 1, measure: FileSize.measure
        )

        let cache = try #require(report.items.first { $0.id == "battlenet-cache" })
        #expect(cache.urls.map { $0.pathComponents.suffix(3).joined(separator: "/") } == ["Shared/Blizzard/Battle.net"])
        #expect(cache.handling == .trash)
        #expect(cache.heldBack == .sharedWithEveryone)
    }

    /// The caches apps keep for every account are measured without what macOS keeps there for its own services,
    /// which belong to other accounts' processes and are never offered.
    @Test func findsTheCachesAppsKeepForEveryAccountWithoutMacOSsOwn() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Library/Caches/org.example.updater/package.bin", bytes: 8_000)
        try directory.file("root/Library/Caches/com.apple.iconservices.store/icons.bin", bytes: 50_000)
        try directory.file("root/Library/Caches/ColorSync/profiles.bin", bytes: 50_000)

        let report = await SpaceInventory.scan(
            home: directory.url.appending(path: "home", directoryHint: .isDirectory),
            root: directory.url.appending(path: "root", directoryHint: .isDirectory),
            minimumSize: 1, measure: FileSize.measure
        )

        let caches = try #require(report.items.first { $0.id == "system-caches" })
        #expect(caches.urls.map { $0.pathComponents.suffix(2).joined(separator: "/") } == ["Library/Caches"])
        #expect(caches.handling == .trash)
        #expect(caches.leavesMacOSsOwn)
        #expect(caches.size.map { $0 >= 8_000 && $0 < 50_000 } == true)
    }

    @Test func everyDefinitionSaysWhatItIsAndWhoOwnsIt() {
        for definition in SpaceInventory.definitions {
            #expect(!definition.id.isEmpty)
            let containers = !definition.containerFolders.isEmpty || definition.groupContainerFolder != nil
            #expect(!definition.paths.isEmpty || containers)
        }
        #expect(Set(SpaceInventory.definitions.map(\.id)).count == SpaceInventory.definitions.count)
    }

    /// Space empties a folder's contents and never the folder, whose name macOS expects to find. So the guard
    /// must refuse each folder and allow a plain item inside it, or the row would be offered and free nothing.
    @Test func whatSpaceCanEmptyIsRefusedItselfAndAllowedInside() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        let guardian = RemovalGuard(environment: SearchEnvironment(homeDirectory: home, rootDirectory: root))
        var checked = 0

        for definition in SpaceInventory.definitions where definition.handling == .trash {
            for path in definition.paths {
                let folder = path.hasPrefix("/")
                    ? root.appending(path: String(path.dropFirst()), directoryHint: .isDirectory)
                    : home.appending(path: path, directoryHint: .isDirectory)
                #expect(!guardian.allowsRemoval(of: folder), "\(definition.id)'s \(path) could be moved whole")
                #expect(
                    guardian.allowsRemoval(of: folder.appending(path: "com.example.app", directoryHint: .isDirectory)),
                    "the guard refuses what is inside \(definition.id)'s \(path), so emptying it frees nothing"
                )
                checked += 1
            }
        }
        #expect(checked > 0, "nothing in the table can be emptied, so the test proves nothing")
    }

    /// Scanning the real Mac must work and change nothing. It walks the real home folder, so it runs only when
    /// asked for (`PEEL_TEST_THIS_MAC=1`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PEEL_TEST_THIS_MAC"] != nil))
    func measuresThisMacWithoutComplaining() async {
        let report = await SpaceInventory.scan()
        #expect(report.storage.total > 0)
        #expect(report.storage.free <= report.storage.total)
        #expect(report.purgeable <= report.storage.total)
        #expect(report.snapshots.allSatisfy { !$0.name.isEmpty })
        #expect(report.items.allSatisfy { !$0.urls.isEmpty })
    }
}
