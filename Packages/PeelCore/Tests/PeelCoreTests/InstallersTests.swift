import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct InstallersTests {
    /// The macOS installers and the firmware are scanned after the downloads, and those later steps must stop
    /// as well.
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...30 {
            try directory.file("Downloads/Installer \(index).dmg", bytes: 16)
        }
        for index in 1...3 {
            try directory.directory("Applications/Install macOS \(index).app/Contents")
            try directory.file("Library/iTunes/iPhone Software Updates/iPhone \(index).ipsw", bytes: 16)
        }
        let unanswered = Unanswered()

        let stop = try await unanswered.stop {
            _ = await Installers.scan(installedApps: [], home: directory.url, root: directory.url, exclusions: .none, minimumSize: 0, measure: unanswered.walk)
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }

    private func app(_ name: String, bundleIdentifier: String) -> InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/\(name).app"), bundleIdentifier: bundleIdentifier, name: name)
    }

    /// Random, so an archive of it is as big as it: zeros shrink to nothing and fall under the floor.
    private func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    private func run(_ tool: String, _ arguments: [String], in folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = folder
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(tool) \(arguments) failed")
    }

    /// Apple ships Xcode as a `.xip`, which can leave gigabytes in Downloads. A `.zip` could hold anything, so it
    /// counts only when it holds one app and nothing else, the way a maker packs one. The app inside is matched to
    /// an installed app, whatever the browser called the file.
    @Test func findsAppsDownloadedAsXipOrZip() async throws {
        let directory = try TemporaryDirectory()
        let build = directory.url.appending(path: "Build", directoryHint: .isDirectory)
        try directory.file("Build/Rectangle.app/Contents/MacOS/Rectangle", contents: randomData(count: 400_000))
        try directory.file("Build/Notes/a.txt", contents: randomData(count: 400_000))
        try directory.file("Downloads/Xcode_26.1.xip", bytes: 400_000)
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", "Rectangle.app", "../Downloads/download (3).zip"], in: build)
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", "Notes", "../Downloads/Notes.zip"], in: build)
        try run("/usr/bin/zip", ["-qr", "../Downloads/Both.zip", "Rectangle.app", "Notes"], in: build)
        try directory.file("Build/Magnet.app/Contents/MacOS/Magnet", contents: randomData(count: 400_000))
        try run("/usr/bin/zip", ["-qr", "../Downloads/Two apps.zip", "Rectangle.app", "Magnet.app"], in: build)
        try directory.directory("Applications")

        let scan = await Installers.scan(
            installedApps: [app("Xcode", bundleIdentifier: "com.apple.dt.Xcode"), app("Rectangle", bundleIdentifier: "com.knollsoft.Rectangle")],
            home: directory.url,
            root: directory.url,
            minimumSize: 100_000
        )

        let installers = scan.items(in: .appInstaller)
        #expect(Set(installers.map(\.name)) == ["Xcode_26.1.xip", "download (3).zip"])
        #expect(installers.first { $0.name.hasSuffix(".xip") }?.installedApp == "Xcode")
        #expect(installers.first { $0.name.hasSuffix(".zip") }?.installedApp == "Rectangle")
    }

    /// An archive past 4 GB or 65,535 entries keeps its directory in ZIP64 records, which `zip -fz` writes on any
    /// archive. Anything that is not a whole archive answers nothing, never a guess.
    @Test func readsTheAppInsideAnArchiveOfEitherKind() throws {
        let directory = try TemporaryDirectory()
        let build = directory.url.appending(path: "Build", directoryHint: .isDirectory)
        try directory.file("Build/Rectangle.app/Contents/MacOS/Rectangle", contents: randomData(count: 1_000))
        try run("/usr/bin/zip", ["-qr", "-fz", "../large.zip", "Rectangle.app"], in: build)
        let large = directory.url.appending(path: "large.zip")
        let whole = try Data(contentsOf: large)
        let cut = try directory.file("cut.zip", contents: whole.dropLast(10))
        let text = try directory.file("notes.zip", contents: Data("not an archive".utf8))

        #expect(ZipDirectory.names(at: large)?.contains("Rectangle.app/Contents/MacOS/Rectangle") == true)
        #expect(Installers.appInside(zip: large) == "Rectangle")
        #expect(ZipDirectory.names(at: cut) == nil)
        #expect(ZipDirectory.names(at: text) == nil)
    }

    @Test func findsBigInstallersAndSaysWhichAppIsAlreadyInstalled() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Downloads/VisualStudioCode-1.99.0.dmg", bytes: 400_000)
        try directory.file("Downloads/SomethingNobodyHas-2.pkg", bytes: 400_000)
        try directory.file("Downloads/small.dmg", bytes: 16)
        try directory.file("Downloads/notes.txt", bytes: 400_000)
        try directory.directory("Applications")

        let scan = await Installers.scan(
            installedApps: [app("Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")],
            home: directory.url,
            root: directory.url,
            minimumSize: 100_000
        )

        let installers = scan.items(in: .appInstaller)
        #expect(Set(installers.map(\.name)) == ["VisualStudioCode-1.99.0.dmg", "SomethingNobodyHas-2.pkg"])
        #expect(installers.first { $0.name.hasPrefix("VisualStudioCode") }?.installedApp == "Visual Studio Code")
        #expect(installers.first { $0.name.hasPrefix("Something") }?.installedApp == nil)
        #expect(installers.allSatisfy { !$0.isReadOnly })
    }

    @Test func findsMacOSInstallersAndDeviceFirmware() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Applications/Install macOS Tahoe.app/Contents/MacOS/app", bytes: 400_000)
        try directory.file("Applications/Safari.app/Contents/MacOS/app", bytes: 400_000)
        try directory.file("Library/iTunes/iPhone Software Updates/iPhone17,1_26.1.ipsw", bytes: 400_000)
        try directory.directory("Downloads")

        let scan = await Installers.scan(installedApps: [], home: directory.url, root: directory.url, minimumSize: 100_000)

        #expect(scan.items(in: .macOSInstaller).map(\.name) == ["Install macOS Tahoe"])
        #expect(scan.items(in: .firmware).map(\.name) == ["iPhone17,1_26.1.ipsw"])
    }

    /// A folder is measured by walking all of it. Only a name that ends like an installer can ever be kept, so
    /// the name is read first: a projects folder in Documents is never walked to find out it is not a disk image.
    @Test func measuresOnlyWhatIsNamedLikeAnInstaller() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Documents/Projects/app/node_modules/left-pad/index.js", bytes: 400_000)
        try directory.file("Downloads/notes.txt", bytes: 400_000)
        try directory.file("Downloads/Thing-1.dmg", bytes: 400_000)
        try directory.directory("Applications")
        let asked = Mutex<[String]>([])

        let scan = await Installers.scan(installedApps: [], home: directory.url, root: directory.url, exclusions: .none, minimumSize: 100_000) { url in
            asked.withLock { $0.append(url.lastPathComponent) }
            return await FileSize.contents(of: url)
        }

        #expect(asked.withLock { $0 } == ["Thing-1.dmg"])
        #expect(scan.items.map(\.name) == ["Thing-1.dmg"])
    }

    /// Leaving the page cancels the scan, and a scan that was canceled measures nothing more.
    @Test func aScanThatWasCanceledStopsMeasuring() async throws {
        let directory = try TemporaryDirectory()
        for index in 0..<12 {
            try directory.file("Downloads/Thing-\(index).dmg", bytes: 400_000)
        }
        try directory.directory("Applications")
        let measured = Mutex(0)
        let home = directory.url

        let scan = Task {
            await Installers.scan(installedApps: [], home: home, root: home, exclusions: .none, minimumSize: 100_000) { _ in
                measured.withLock { $0 += 1 }
                while !Task.isCancelled { await Task.yield() }
                return FolderContents(size: 400_000, holdsRepository: false)
            }
        }
        while measured.withLock({ $0 }) == 0 { await Task.yield() }
        scan.cancel()
        _ = await scan.value

        #expect(measured.withLock { $0 } == 1, "it went on measuring after it was canceled")
    }

    /// A device backup can hold hundreds of thousands of files, so it is the most likely to run out of time. An
    /// unknown size is not zero: the backup is listed first, where the biggest go, and its size reads as unknown.
    @Test func aBackupThatDidNotAnswerInTimeIsNotReadAsEmpty() async throws {
        let directory = try TemporaryDirectory()
        let slow = try directory.directory("Library/Application Support/MobileSync/Backup/slow")
        let quick = try directory.directory("Library/Application Support/MobileSync/Backup/quick")
        try directory.file("Library/Application Support/MobileSync/Backup/quick/blob", bytes: 400_000)
        try directory.directory("Applications")

        let scan = await Installers.scan(installedApps: [], home: directory.url, root: directory.url, exclusions: .none, minimumSize: 100_000) { url in
            url.lastPathComponent == "slow" ? nil : await FileSize.contents(of: url)
        }

        let backups = scan.items(in: .deviceBackup)
        #expect(backups.map(\.url.lastPathComponent) == [slow.lastPathComponent, quick.lastPathComponent])
        #expect(backups.first?.size == nil)
        #expect(try #require(backups.last?.size) >= 400_000)
    }

    /// A package can be a folder. One that did not answer may be any size, so the floor does not drop it, and what
    /// is inside is not known, so it is left for the person to choose.
    @Test func keepsAnInstallerWhoseSizeIsNotKnown() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Downloads/Suite.mpkg/Contents/Packages/one.pkg", bytes: 16)
        try directory.directory("Applications")

        let scan = await Installers.scan(installedApps: [], home: directory.url, root: directory.url, exclusions: .none, minimumSize: 100_000) { _ in nil }

        #expect(scan.items(in: .appInstaller).map(\.name) == ["Suite.mpkg"])
        #expect(scan.items.first?.size == nil)
        #expect(scan.items.first?.heldBack == .notMeasured)
    }

    /// A backup is the only thing here Peel won't move: it says what is in it and leaves it to Finder.
    @Test func readsWhatABackupSaysAboutItselfAndLeavesItAlone() async throws {
        let directory = try TemporaryDirectory()
        let backup = try directory.directory("Backup/00008030-001234567890ABCD")
        let info: [String: Any] = [
            "Device Name": "Zoë's iPhone",
            "Product Name": "iPhone 17 Pro",
            "Product Version": "26.1",
            "Last Backup Date": Date(timeIntervalSince1970: 1_700_000_000),
        ]
        try (PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0))
            .write(to: backup.appending(path: "Info.plist"))
        try (PropertyListSerialization.data(fromPropertyList: ["IsEncrypted": true], format: .xml, options: 0))
            .write(to: backup.appending(path: "Manifest.plist"))

        let items = await Installers.backups(in: directory.url.appending(path: "Backup", directoryHint: .isDirectory), measure: LeftoverScanner.walk)
        let item = try #require(items.first)

        #expect(item.name == "Zoë's iPhone")
        #expect(item.notes == [.name("iPhone 17 Pro"), .name("iOS 26.1"), .encrypted])

        // An iPad runs iPadOS, which its model code says.
        let tablet = try directory.directory("Backup/00008112-00AB")
        try (PropertyListSerialization.data(fromPropertyList: ["Product Type": "iPad13,4", "Product Version": "26.1"], format: .xml, options: 0))
            .write(to: tablet.appending(path: "Info.plist"))
        let tablets = await Installers.backups(in: directory.url.appending(path: "Backup", directoryHint: .isDirectory), measure: LeftoverScanner.walk)
        #expect(tablets.first { $0.url.lastPathComponent == "00008112-00AB" }?.notes == [.name("iPad13,4"), .name("iPadOS 26.1")])
        #expect(item.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(item.isReadOnly)
        #expect(item.kind == .deviceBackup)
    }

    @Test func honorsExclusionsAndTheSizeFloor() async throws {
        let directory = try TemporaryDirectory()
        let installer = try directory.file("Downloads/Thing-1.dmg", bytes: 400_000)
        try directory.directory("Applications")

        let kept = await Installers.scan(
            installedApps: [],
            home: directory.url,
            root: directory.url,
            exclusions: Exclusions(paths: [installer]),
            minimumSize: 100_000
        )
        #expect(kept.items.isEmpty)

        let tooSmall = await Installers.scan(installedApps: [], home: directory.url, root: directory.url, minimumSize: 1_000_000)
        #expect(tooSmall.items.isEmpty)
    }

    /// `/Library/Updates` belongs to Software Update, and a backup is never Peel's to move.
    @Test func theGuardRefusesStagedSystemUpdates() throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(homeDirectory: directory.url, rootDirectory: directory.url.appending(path: "root"))
        let guardian = RemovalGuard(environment: environment)

        #expect(!guardian.allowsRemoval(of: URL(filePath: "/Library/Updates")))
        #expect(!guardian.allowsRemoval(of: URL(filePath: "/Library/Updates/Rosetta")))
        #expect(!guardian.allowsRemoval(of: directory.url.appending(path: "Library/Application Support/MobileSync/Backup/00008030")))
        #expect(guardian.allowsRemoval(of: directory.url.appending(path: "Downloads/Thing-1.dmg")))
    }

    @Test func matchesAnInstallerOnlyToANameThatMeansSomething() {
        let apps = [app("Setup", bundleIdentifier: "com.example.setup"), app("Bear", bundleIdentifier: "net.shinyfrog.bear")]

        #expect(Installers.installedApp(for: URL(filePath: "/x/Bear-2.4.dmg"), in: apps)?.name == "Bear")
        #expect(Installers.installedApp(for: URL(filePath: "/x/Setup-1.0.dmg"), in: apps) == nil)
        #expect(Installers.installedApp(for: URL(filePath: "/x/Unrelated.dmg"), in: apps) == nil)
    }

    /// "Already installed" is what makes someone delete their only copy, so it is the name before the version
    /// that has to match, not any name the file name begins with.
    @Test func doesNotCallAnotherProductsInstallerTheInstalledApp() {
        let apps = [app("Xcode", bundleIdentifier: "com.apple.dt.Xcode"), app("Arc", bundleIdentifier: "company.thebrowser.Browser")]

        #expect(Installers.installedApp(for: URL(filePath: "/x/Xcodes-1.4.dmg"), in: apps) == nil)
        #expect(Installers.installedApp(for: URL(filePath: "/x/Archiver-4.dmg"), in: apps) == nil)
        // The same name, written the ways installers write it.
        #expect(Installers.installedApp(for: URL(filePath: "/x/Xcode.dmg"), in: apps)?.name == "Xcode")
        #expect(Installers.installedApp(for: URL(filePath: "/x/Xcode_26.1.xip"), in: apps)?.name == "Xcode")
        #expect(Installers.installedApp(for: URL(filePath: "/x/Xcode 26.dmg"), in: apps)?.name == "Xcode")
        #expect(Installers.installedApp(for: URL(filePath: "/x/Arc-arm64.dmg"), in: apps)?.name == "Arc")
        #expect(Installers.installedApp(for: URL(filePath: "/x/Arc universal.dmg"), in: apps)?.name == "Arc")

        // Other people's products whose names begin with an installed app's.
        let others = [app("Bear", bundleIdentifier: "net.shinyfrog.bear"), app("Signal", bundleIdentifier: "org.whispersystems.signal"), app("Notion", bundleIdentifier: "notion.id")]
        #expect(Installers.installedApp(for: URL(filePath: "/x/Bearable-1.2.dmg"), in: others) == nil)
        #expect(Installers.installedApp(for: URL(filePath: "/x/SignalRGB.dmg"), in: others) == nil)
        #expect(Installers.installedApp(for: URL(filePath: "/x/Notion Calendar.dmg"), in: others) == nil)
        #expect(Installers.installedApp(for: URL(filePath: "/x/Notion-2.3.dmg"), in: others)?.name == "Notion")
    }

    /// A word that only begins like one an installer adds is another word: `Macros` is not `mac`.
    @Test func aWordAfterTheNameCountsOnlyWhole() {
        let apps = [
            app("Alfred", bundleIdentifier: "com.runningwithcrayons.Alfred"), app("Figma", bundleIdentifier: "com.figma.Desktop"),
        ]

        #expect(Installers.installedApp(for: URL(filePath: "/x/Alfred-Macros-Pack.dmg"), in: apps) == nil)
        #expect(Installers.installedApp(for: URL(filePath: "/x/Figma-Fullscreen-Helper.dmg"), in: apps) == nil)
        #expect(Installers.installedApp(for: URL(filePath: "/x/Alfred_5.5.1_2273.dmg"), in: apps)?.name == "Alfred")
        #expect(Installers.installedApp(for: URL(filePath: "/x/Figma-mac-x86_64.dmg"), in: apps)?.name == "Figma")
        #expect(Installers.installedApp(for: URL(filePath: "/x/FigmaSetup.dmg"), in: apps)?.name == "Figma")
        #expect(Installers.installedApp(for: URL(filePath: "/x/Figma-v124.dmg"), in: apps)?.name == "Figma")
    }
}
