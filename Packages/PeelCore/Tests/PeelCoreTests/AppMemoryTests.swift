import Foundation
@testable import PeelCore
import Testing

struct AppMemoryTests {
    private func app(_ name: String, _ bundleIdentifier: String, isSystemProtected: Bool = false) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory),
            bundleIdentifier: bundleIdentifier,
            name: name,
            teamIdentifier: "ABCDE12345",
            isSystemProtected: isSystemProtected
        )
    }

    @Test func keepsWhatItHasSeen() async throws {
        let directory = try TemporaryDirectory()
        let memory = AppMemory(url: directory.url.appending(path: "apps.json"))

        let first = await memory.remember([app("Bear", "net.shinyfrog.bear"), app("Zed", "dev.zed.Zed")])
        #expect(Set(first.map(\.bundleIdentifier)) == ["net.shinyfrog.bear", "dev.zed.Zed"])
        #expect(first.first { $0.bundleIdentifier == "net.shinyfrog.bear" }?.lastPath == "/Applications/Bear.app")

        let second = await memory.remember([app("Bear", "net.shinyfrog.bear")])
        #expect(Set(second.map(\.bundleIdentifier)) == ["net.shinyfrog.bear", "dev.zed.Zed"], "an app it saw before was forgotten")
    }

    /// A memory that leads nowhere cannot be read, so it is left as it is rather than replaced by a new file.
    @Test func leavesAMemoryItCannotReachAsItIs() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "apps.json")
        let path = url.path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: "/nowhere/apps.json")

        _ = await AppMemory(url: url).remember([app("Bear", "net.shinyfrog.bear")])

        let kind = try FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
        #expect(kind == .typeSymbolicLink, "the memory was written over")
    }

    /// macOS's own apps come and go with the system, so remembering them says nothing useful.
    @Test func leavesTheSystemsOwnAppsOut() async throws {
        let directory = try TemporaryDirectory()
        let memory = AppMemory(url: directory.url.appending(path: "apps.json"))

        let remembered = await memory.remember([
            app("Safari", "com.apple.Safari", isSystemProtected: true),
            app("Bear", "net.shinyfrog.bear"),
        ])
        #expect(remembered.map(\.bundleIdentifier) == ["net.shinyfrog.bear"])
    }

    @Test func namesLeftoverFilesAfterTheAppThatLeftThem() {
        let remembered = [
            RememberedApp(bundleIdentifier: "com.example.app", name: "Example", teamIdentifier: nil, lastSeen: .now, lastPath: "/Applications/Example.app"),
            RememberedApp(bundleIdentifier: "com.example.app.pro", name: "Example Pro", teamIdentifier: nil, lastSeen: .now, lastPath: "/Applications/Example Pro.app"),
        ]

        #expect(AppMemory.app(for: "com.example.app", in: remembered)?.name == "Example")
        #expect(AppMemory.app(for: "COM.EXAMPLE.APP", in: remembered)?.name == "Example")
        // The longest match wins, so a helper isn't credited to the shorter name.
        #expect(AppMemory.app(for: "com.example.app.pro.helper", in: remembered)?.name == "Example Pro")
        #expect(AppMemory.app(for: "com.example.app.helper", in: remembered)?.name == "Example")
        #expect(AppMemory.app(for: "com.other.thing", in: remembered) == nil)
        #expect(AppMemory.app(for: "com.example.apple", in: remembered) == nil, "a longer name was mistaken for a child")
    }

    /// Two components name a maker, not an app: everything that maker ever shipped starts with them.
    @Test func aMakersNameAloneIsNoAppsPrefix() {
        let remembered = [
            RememberedApp(bundleIdentifier: "md.obsidian", name: "Obsidian", teamIdentifier: nil, lastSeen: .now, lastPath: "/Applications/Obsidian.app"),
        ]

        #expect(AppMemory.app(for: "md.obsidian", in: remembered)?.name == "Obsidian")
        #expect(AppMemory.app(for: "md.obsidian.helper", in: remembered) == nil)
    }

    @Test func anAppOnADiskThatIsNotConnectedIsStillInstalled() {
        let place = "/Volumes/Peel Not Connected \(UUID().uuidString)/Applications/Example.app"
        let remembered = RememberedApp(
            bundleIdentifier: "org.example.app", name: "Example", teamIdentifier: nil, lastSeen: .now, lastPath: place
        )

        #expect(remembered.stillInstalled()?.bundleIdentifier == "org.example.app")
        let gone = RememberedApp(
            bundleIdentifier: "org.example.app", name: "Example", teamIdentifier: nil, lastSeen: .now,
            lastPath: "/Applications/Peel Gone \(UUID().uuidString).app"
        )
        #expect(gone.stillInstalled() == nil)
    }

    @Test func survivesBeingWrittenAndReadBack() async throws {
        let directory = try TemporaryDirectory()
        let memory = AppMemory(url: directory.url.appending(path: "nested/apps.json"))

        _ = await memory.remember([app("Bear", "net.shinyfrog.bear")])
        let read = await memory.load()
        #expect(read.map(\.name) == ["Bear"])
        #expect(read.first?.teamIdentifier == "ABCDE12345")
    }

    /// This file is the only record of the names and places of apps that are gone. A row that cannot be read
    /// costs only that row, and the damaged file is kept under another name.
    @Test func keepsTheAppsItCanReadWhenOneRowMakesNoSense() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "apps.json")
        let memory = AppMemory(url: url)
        _ = await memory.remember([app("Bear", "net.shinyfrog.bear"), app("Zed", "dev.zed.Zed")])
        var rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        rows.append(["bundleIdentifier": 1])
        let damaged = try JSONSerialization.data(withJSONObject: rows)
        try damaged.write(to: url)

        let remembered = await memory.remember([app("Arc", "company.thebrowser.Browser")])

        #expect(Set(remembered.map(\.bundleIdentifier)) == ["net.shinyfrog.bear", "dev.zed.Zed", "company.thebrowser.Browser"])
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false)).filter
        { $0.contains("damaged") }
        #expect(kept.count == 1, "the file as it was is not kept: \(kept)")
    }

    /// A file that is there and cannot be read says nothing about what it holds, so it is never written over.
    @Test(.permissionsHold) func leavesAFileItCannotReadAlone() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "apps.json")
        let memory = AppMemory(url: url)
        _ = await memory.remember([app("Bear", "net.shinyfrog.bear")])
        let before = try Data(contentsOf: url)
        try directory.setPermissions(0o000, of: "apps.json")
        defer { try? directory.setPermissions(0o644, of: "apps.json") }

        let remembered = await memory.remember([app("Zed", "dev.zed.Zed")])

        #expect(remembered.map(\.bundleIdentifier) == ["dev.zed.Zed"], "what is installed now is still known for this run")
        try directory.setPermissions(0o644, of: "apps.json")
        #expect(try Data(contentsOf: url) == before, "a file that could not be read was written over")
    }

    /// Two refreshes can overlap, and each reads, merges, and writes: the later write must not lose the earlier.
    @Test func keepsEveryAppWhenTwoRefreshesOverlap() async throws {
        let directory = try TemporaryDirectory()
        let memory = AppMemory(url: directory.url.appending(path: "apps.json"))

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask { _ = await memory.remember([app("App\(index)", "com.example.app\(index)")]) }
            }
        }

        #expect(await memory.load().count == 20)
    }

    @Test func dropsTheLeastRecentlySeenPastTheCap() async throws {
        let directory = try TemporaryDirectory()
        let memory = AppMemory(url: directory.url.appending(path: "apps.json"))
        let old = Date(timeIntervalSince1970: 1_000)
        _ = await memory.remember((0..<AppMemory.maximumApps).map { app("Old\($0)", "com.example.old\($0)") }, now: old)

        let remembered = await memory.remember([app("New", "com.example.new")])

        #expect(remembered.count == AppMemory.maximumApps)
        #expect(remembered.contains { $0.bundleIdentifier == "com.example.new" })
    }

    @Test func namesAnOrphanGroupAfterTheAppItRemembers() {
        let remembered = [
            RememberedApp(bundleIdentifier: "com.example.app", name: "Example", teamIdentifier: nil, lastSeen: .now, lastPath: "/Applications/Example.app"),
        ]
        let item = OrphanItem(
            url: URL(filePath: "/Users/x/Library/Caches/com.example.app"),
            kind: .caches,
            size: 10,
            modificationDate: nil,
            requiresPrivileges: false
        )

        let groups = OrphanScanner.group([(identifier: "com.example.app", item: item)], remembered: remembered)
        #expect(groups.first?.title == "Example")
        #expect(groups.first?.rememberedApp?.lastPath == "/Applications/Example.app")

        let unknown = OrphanScanner.group([(identifier: "com.example.app", item: item)])
        #expect(unknown.first?.title == "com.example.app")
        #expect(unknown.first?.rememberedApp == nil)
    }
}
