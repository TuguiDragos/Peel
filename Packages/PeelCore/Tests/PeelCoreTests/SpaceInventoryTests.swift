import Foundation
@testable import PeelCore
import PeelPrivileged
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
            _ = await SpaceInventory.scan(
                home: directory.url,
                root: directory.url,
                minimumSize: 1,
                measure: unanswered.measure
            )
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < SpaceInventory.definitions.count)
        #expect(stop.askedAfter == 0)
    }

    /// macOS empties it only in a safe boot (`man confstr`); its own files there, some unreadable, aren't measured.
    @Test(.permissionsHold) func listsTheFolderMacOSGivesTheAccountForCaches() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("C/org.example.editor.helper/com.apple.metal/shaders.data", bytes: 400)
        try directory.file("C/com.apple.WebKit.WebContent.Sandbox", bytes: 16)
        try directory.setPermissions(0, of: "C/com.apple.WebKit.WebContent.Sandbox")
        defer { try? directory.setPermissions(0o644, of: "C/com.apple.WebKit.WebContent.Sandbox") }
        let userCache = directory.url.appending(path: "C", directoryHint: .isDirectory)

        let report = await SpaceInventory.scan(
            home: directory.url.appending(path: "home"), root: directory.url.appending(path: "root"),
            userCache: userCache, minimumSize: 1, measure: FileSize.measure
        )

        let item = try #require(report.items.first { $0.id == "user-caches" })
        #expect(item.urls == [userCache])
        #expect(item.handling == .trash)
        #expect(item.leavesMacOSsOwn)
        #expect(item.size != nil, "what macOS keeps was measured")
    }

    @Test func reportsOnlyWhatIsBigEnough() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Logs/big.log", bytes: 400_000)
        try directory.file(".colima/machine/disk.img", bytes: 16)

        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        let report = await SpaceInventory.scan(
            home: directory.url, root: root, minimumSize: 100_000, measure: FileSize.measure
        )
        #expect(report.items.map(\.id) == ["logs"])
        #expect(report.items.first?.handling == .trash)

        let everything = await SpaceInventory.scan(
            home: directory.url, root: root, minimumSize: 1, measure: FileSize.measure
        )
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
        try directory.file("home/Library/Logs/big.log", bytes: 400_000)
        try directory.setPermissions(0, of: "home/Library/Logs")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Logs") }

        let report = await SpaceInventory.scan(
            home: directory.url.appending(path: "home", directoryHint: .isDirectory),
            root: directory.url.appending(path: "root", directoryHint: .isDirectory),
            minimumSize: 100_000,
            measure: FileSize.measure
        )
        #expect(report.items.map(\.id) == ["logs"])
        #expect(report.items.first?.size == nil)
        #expect(!report.needsFullDiskAccess, "ordinary permissions were read as a refusal Full Disk Access would lift")
    }

    @Test(.permissionsHold) func keepsASharedAreaItCannotListAsUnknown() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Library/Logs/org.example.tool/run.log", bytes: 400_000)
        try directory.setPermissions(0, of: "root/Library/Logs")
        defer { try? directory.setPermissions(0o755, of: "root/Library/Logs") }

        let report = await SpaceInventory.scan(
            home: directory.url.appending(path: "home", directoryHint: .isDirectory),
            root: directory.url.appending(path: "root", directoryHint: .isDirectory),
            minimumSize: 100_000,
            measure: FileSize.measure
        )
        #expect(report.items.map(\.id) == ["system-logs"])
        #expect(report.items.first?.size == nil)
    }

    @Test func leavesOutWhatIsExcludedAndWhatItHolds() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Parallels/Example.pvm/disk.hdd", bytes: 400_000)
        try directory.file("Library/Caches/org.example.kept/blob", bytes: 300_000)
        try directory.file("Library/Caches/org.example.excluded/blob", bytes: 500_000)
        let exclusions = Exclusions(paths: [
            directory.url.appending(path: "Parallels"),
            directory.url.appending(path: "Library/Caches/org.example.excluded"),
        ])

        let report = await SpaceInventory.scan(
            home: directory.url, root: directory.url, minimumSize: 1, exclusions: exclusions, measure: FileSize.measure
        )

        #expect(!report.items.contains { $0.id == "parallels" })
        let caches = try #require(report.items.first { $0.id == "caches" })
        let kept = await FileSize.reclaimableSize(of: directory.url.appending(path: "Library/Caches/org.example.kept"))
        #expect(caches.size == kept)
    }

    @Test func leavesOutWhatAnExcludedAppKeepsInItsOwnFolders() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Caches/org.example.kept/blob", bytes: 300_000)
        try directory.file("Library/Caches/org.example.Notes/blob", bytes: 500_000)
        try directory.file("Library/Containers/org.example.Notes/Data/Library/Caches/blob", bytes: 500_000)

        let report = await SpaceInventory.scan(
            home: directory.url, root: directory.url, minimumSize: 1,
            exclusions: Exclusions(bundleIdentifiers: ["org.example.Notes"]), measure: FileSize.measure
        )

        let caches = try #require(report.items.first { $0.id == "caches" })
        let kept = await FileSize.reclaimableSize(of: directory.url.appending(path: "Library/Caches/org.example.kept"))
        #expect(caches.size == kept)
        #expect(!report.items.flatMap(\.urls).contains { $0.path(percentEncoded: false).contains("org.example.Notes") })
    }

    @Test func anExcludedPlaceThatCannotBeMeasuredLeavesTheAreaUnknown() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Caches/org.example.kept/blob", bytes: 300_000)
        try directory.file("Library/Caches/org.example.excluded/blob", bytes: 500_000)
        let excluded = directory.url.appending(path: "Library/Caches/org.example.excluded")

        let report = await SpaceInventory.scan(
            home: directory.url, root: directory.url, minimumSize: 1, exclusions: Exclusions(paths: [excluded])
        ) { url in
            url.lastPathComponent == excluded.lastPathComponent ? nil : await FileSize.measure(url)
        }

        #expect(report.items.first { $0.id == "caches" }?.size == nil)
    }

    @Test func leavesWhatOthersOwnToThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".colima/machine/disk.img", bytes: 4096)

        let report = await SpaceInventory.scan(
            home: directory.url,
            root: directory.url,
            minimumSize: 1,
            measure: FileSize.measure
        )
        let machines = try #require(report.items.first { $0.id == "colima" })
        #expect(machines.isReadOnly)
        #expect(machines.category == .virtualMachines)
    }

    /// macOS 26 keeps the downloaded aerials per user, not in the shared folder macOS 14 and 15 used.
    @Test func findsTheAerialWallpapersWhereMacOS26KeepsThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Application Support/com.apple.wallpaper/aerials/videos/a.mov", bytes: 400_000)

        let report = await SpaceInventory.scan(
            home: directory.url,
            root: directory.url,
            minimumSize: 100_000,
            measure: FileSize.measure
        )
        #expect(report.items.map(\.id) == ["wallpapers"])
    }

    /// The simulator caches belong to Developer, which selects them, so Space leaves them out. The runtimes, the
    /// larger part, sit outside the home folder and are counted here.
    @Test func countsTheSimulatorRuntimesAndLeavesTheCachesToDeveloper() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Developer/CoreSimulator/Devices/one/data.bin", bytes: 400_000)
        try directory.file("Library/Developer/CoreSimulator/Caches/dyld/shared.bin", bytes: 400_000)
        try directory.file("Library/Developer/CoreSimulator/Images/runtime.dmg", bytes: 400_000)

        let report = await SpaceInventory.scan(
            home: directory.url,
            root: directory.url,
            minimumSize: 100_000,
            measure: FileSize.measure
        )
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

    /// The logs every account shares are measured without what macOS writes there for its own services, and the
    /// crash reports without the folders macOS files them into.
    @Test func findsTheLogsAndReportsEveryAccountSharesWithoutMacOSsOwn() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Library/Logs/org.example.tool/run.log", bytes: 8_000)
        try directory.file("root/Library/Logs/WindowServer/session.log", bytes: 50_000)
        try directory.file("root/Library/Logs/DiagnosticReports/Example_2026-09-28.ips", bytes: 4_000)
        try directory.file("root/Library/Logs/DiagnosticReports/Retired/panic-full.ips", bytes: 50_000)

        let report = await SpaceInventory.scan(
            home: directory.url.appending(path: "home", directoryHint: .isDirectory),
            root: directory.url.appending(path: "root", directoryHint: .isDirectory),
            minimumSize: 1, measure: FileSize.measure
        )

        let logs = try #require(report.items.first { $0.id == "system-logs" })
        #expect(logs.urls.map { $0.pathComponents.suffix(2).joined(separator: "/") } == [
            "Library/Logs", "Logs/DiagnosticReports",
        ])
        #expect(logs.size.map { $0 >= 12_000 && $0 < 50_000 } == true)
    }

    @Test func findsEveryPlaceOfEveryAreaItKnows() async throws {
        let directory = try TemporaryDirectory()
        let (home, root) = (try directory.directory("home"), try directory.directory("root"))
        var expected: Set<String> = []
        for definition in SpaceInventory.definitions {
            let places = definition.paths.map { $0.hasPrefix("/") ? "root" + $0 : "home/" + $0 }
                + definition.containerFolders.map { "home/Library/Containers/org.example.app/\($0)" }
                + (definition.groupContainerFolder.map { ["home/Library/Group Containers/ABCDE12345.org.example.group/\($0)"] } ?? [])
            for place in places {
                try directory.file("\(place)/org.example.kept/content", bytes: 8_000)
                expected.insert("\(definition.id): \(place)")
            }
        }

        let report = await SpaceInventory.scan(home: home, root: root, minimumSize: 1, measure: FileSize.measure)

        let inside = directory.url.lastPathComponent + "/"
        let places = report.items.flatMap { item in
            item.urls.map { url in
                let path = url.path(percentEncoded: false).components(separatedBy: inside).last ?? ""
                return (item: item, path: path.hasSuffix("/") ? String(path.dropLast()) : path)
            }
        }
        let found = Set(places.map { "\($0.item.id): \($0.path)" })
        #expect(expected.subtracting(found).isEmpty, "\(expected.subtracting(found).sorted())")
        // A place in two areas, or inside a place measured whole, would count its bytes twice in the total. An area
        // that leaves macOS's own, or offers only the files of a place of its own, measures what is in its places one
        // by one, and passes over a place of its own.
        let twice = places.filter { place in
            places.contains { other in
                let isAnotherArea = other.item.id != place.item.id
                let measuresOneByOne = other.item.leavesMacOSsOwn || !other.item.onlyFilesIn.isEmpty
                return (other.path == place.path && isAnotherArea)
                    || (place.path.hasPrefix(other.path + "/") && (isAnotherArea || !measuresOneByOne))
            }
        }
        #expect(twice.isEmpty, "counted twice: \(twice.map(\.path).sorted())")
    }

    @Test func everyDefinitionSaysWhatItIsAndWhoOwnsIt() {
        for definition in SpaceInventory.definitions {
            #expect(!definition.id.isEmpty)
            let containers = !definition.containerFolders.isEmpty || definition.groupContainerFolder != nil
            #expect(!definition.paths.isEmpty || containers || definition.isTheUserCacheFolder)
        }
        #expect(Set(SpaceInventory.definitions.map(\.id)).count == SpaceInventory.definitions.count)
    }

    @Test func theSimulatorsAreaGivesApplesCommandsThatThisMacsSimctlKnows() throws {
        let simulators = try #require(SpaceInventory.definitions.first { $0.id == "simulators" })
        #expect(simulators.commands == ["xcrun simctl runtime delete --outdated", "xcrun simctl delete unavailable"])
        #expect(try simctlHelp("runtime").contains("--outdated"))
        #expect(try simctlHelp("delete").contains("unavailable"))
    }

    @Test func showsRustToolchainsAndAndroidNDKsForTheirToolsToRemove() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".rustup/toolchains/stable-aarch64-apple-darwin/bin/rustc", bytes: 400_000)
        try directory.file("Library/Android/sdk/ndk/27.2.12479018/source.properties", bytes: 400_000)

        let report = await SpaceInventory.scan(
            home: directory.url, root: directory.url, minimumSize: 100_000, measure: FileSize.measure
        )

        let rust = try #require(report.items.first { $0.id == "rust-toolchains" })
        #expect(rust.isReadOnly)
        #expect(rust.commands == ["rustup toolchain list", "rustup toolchain uninstall <name>"])
        let ndk = try #require(report.items.first { $0.id == "android-ndk" })
        #expect(ndk.isReadOnly)
        #expect(ndk.commands == [#"~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager --uninstall "ndk;<version>""#])
    }

    @Test func colimaIsToldToDeleteItsDataDiskToo() throws {
        let colima = try #require(SpaceInventory.definitions.first { $0.id == "colima" })
        #expect(colima.commands == ["colima delete --data"])
    }

    @Test func onlyAnAreaPeelLeavesAloneGivesCommands() {
        for definition in SpaceInventory.definitions where !definition.commands.isEmpty {
            #expect(definition.handling == .readOnly, "\(definition.id)")
        }
    }

    private func simctlHelp(_ topic: String) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "help", topic]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Space says it leaves a read only area to the app that made it, so nothing in one is what Developer
    /// selects for the person to remove.
    @Test func noReadOnlyAreaHoldsWhatDeveloperSelects() {
        let selected: Set<DeveloperEnvironment.ContentKind> = [.buildData, .downloads, .cache, .logs]
        for area in SpaceInventory.definitions where area.handling == .readOnly {
            for path in area.paths {
                for tool in DeveloperCaches.definitions {
                    for folder in tool.folders where selected.contains(folder.kind) {
                        let isInside = PathComponents.isPath(folder.path, atOrInside: path)
                        #expect(!isInside, "\(area.id) holds \(folder.path)")
                    }
                }
            }
        }
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

    @Test func knowsNoPurgeableSpaceForAVolumeItCannotRead() {
        #expect(SpaceInventory.purgeableSpace(of: URL(filePath: "/Volumes/org.example.missing")) == nil)
        #expect(SpaceInventory.purgeableSpace(of: .homeDirectory) != nil)
    }

    /// Scanning the real Mac must work and change nothing. It walks the real home folder, so it runs only when
    /// asked for (`PEEL_TEST_THIS_MAC=1`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PEEL_TEST_THIS_MAC"] != nil))
    func measuresThisMacWithoutComplaining() async {
        let report = await SpaceInventory.scan()
        #expect(report.storage.total > 0)
        #expect(report.storage.free <= report.storage.total)
        #expect((report.purgeable ?? 0) <= report.storage.total)
        #expect(report.snapshots?.allSatisfy { !$0.name.isEmpty } == true)
        #expect(report.items.allSatisfy { !$0.urls.isEmpty })
    }
}
