import Foundation
import PeelPrivileged
import Synchronization
@testable import PeelCore
import Testing

struct LeftoverScannerTests {
    /// A file inside the recent documents folder is also inside Application Support, which is looked into two
    /// levels deep. Between two claims of equal strength, the row takes the location nearer the file, so what it
    /// says does not depend on which of the two searches ended first.
    @Test func twoEqualClaimsOnOneFileGiveOneRowWhicheverSearchEndsFirst() {
        let support = SearchLocation(kind: .applicationSupport, url: URL(filePath: "/Users/x/Library/Application Support", directoryHint: .isDirectory))
        let recent = SearchLocation(
            kind: .recentDocuments,
            url: support.url.appending(path: "com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments", directoryHint: .isDirectory)
        )
        func found(in location: SearchLocation) -> (location: SearchLocation, leftovers: [Leftover]) {
            let leftover = Leftover(
                url: recent.url.appending(path: "com.example.app.sfl3"), kind: location.kind,
                match: LeftoverMatch(reason: .bundleIdentifier, confidence: .likely, sharedWith: []),
                size: 10,
                isMeasured: true,
                requiresPrivileges: false
            )
            return (location, [leftover])
        }

        #expect(LeftoverScanner.merged([found(in: support), found(in: recent)]).map(\.kind) == [.recentDocuments])
        #expect(LeftoverScanner.merged([found(in: recent), found(in: support)]).map(\.kind) == [.recentDocuments])
    }

    @Test func findsAFolderAnAppHidWithADotBeforeItsIdentifier() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Application Support/.org.example.app.backups")
        try directory.file("home/Library/Preferences/.org.example.app.plist")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let app = InstalledApp(
            url: try directory.directory("root/Applications/Example.app"),
            bundleIdentifier: "org.example.app",
            name: "Example"
        )

        let plan = await Uninstallation.prepare(app, installedApps: [app], environment: environment)

        let backups = try #require(plan.scan.leftovers.first { $0.url.lastPathComponent == ".org.example.app.backups" })
        #expect(plan.suggestedSelection(canUseHelper: false).contains(backups.url))
        #expect(!plan.scan.leftovers.contains { $0.url.lastPathComponent == ".org.example.app.plist" })
    }

    /// Folders that no app claims are looked into one at a time, so the scan has to notice a stop between them.
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...30 {
            try directory.directory("home/Library/Application Support/Vendor \(index)/net.example.client")
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory),
            userCacheDirectory: directory.url.appending(path: "var/C", directoryHint: .isDirectory),
            userTemporaryDirectory: directory.url.appending(path: "var/T", directoryHint: .isDirectory)
        )
        let unanswered = Unanswered()
        let scanner = LeftoverScanner(environment: environment, measure: unanswered.walk)
        let tunewell = tunewell

        let stop = try await unanswered.stop {
            _ = await scanner.scan(tunewell, installedApps: [tunewell])
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }

    private let tunewell = InstalledApp(
        url: URL(filePath: "/Applications/Tunewell.app"),
        bundleIdentifier: "net.example.client",
        name: "Tunewell"
    )

    private func environment(in directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory),
            userCacheDirectory: directory.url.appending(path: "var/C", directoryHint: .isDirectory),
            userTemporaryDirectory: directory.url.appending(path: "var/T", directoryHint: .isDirectory)
        )
    }

    /// Another copy of an app that macOS knows outside the Applications folders uses the same files. Every Mac has one
    /// of the character palette in its input methods folder, so a copy of it in Applications shares its settings, and
    /// that copy is counted once when the list of apps holds it too.
    /// A preference file whose bytes are not a property list holds settings nobody can read, so its row says so. A
    /// file that reads as one does not.
    @Test func marksAPreferenceFileThatIsNoPropertyList() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Hexachord.app"),
            bundleIdentifier: "org.example.hexachord",
            name: "Hexachord"
        )
        try directory.file("home/Library/Preferences/org.example.hexachord.plist", contents: Data("<plist".utf8))
        let fine = try PropertyListSerialization.data(fromPropertyList: ["Volume": 3], format: .binary, options: 0)
        try directory.file("home/Library/Preferences/org.example.hexachord.helper.plist", contents: fine)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])

        let damaged = scan.leftovers.filter(\.holdsDamagedSettings).map(\.url.lastPathComponent)
        #expect(damaged == ["org.example.hexachord.plist"])
        #expect(scan.leftovers.contains { $0.url.lastPathComponent == "org.example.hexachord.helper.plist" })
    }

    /// A Safari web app keeps its data in a container inside Safari's own web app container, and its settings beside
    /// every app's. Both are found when it is removed, and Safari's container itself never is.
    @Test func findsWhatASafariWebAppKeptInsideSafarisContainer() async throws {
        let directory = try TemporaryDirectory()
        let identifier = "com.apple.Safari.WebApp.0E4F6A2C-1B3D-4E5F-8A9B-0C1D2E3F4A5B"
        let webApps = "home/Library/Containers/com.apple.Safari.WebApp/Data/Library/Containers"
        try directory.file("\(webApps)/\(identifier)/Library/WebApp/PerSiteZoomPreferences.plist", bytes: 4096)
        try directory.file("\(webApps)/com.apple.Safari.WebApp.1A2B3C4D-0000-4000-8000-000000000000/Library/x.plist")
        try directory.file("home/Library/Preferences/\(identifier).plist", bytes: 4096)
        let wiki = InstalledApp(
            url: URL(filePath: "/Users/x/Applications/Wiki.app"),
            bundleIdentifier: identifier,
            name: "Wiki",
            webApp: .safari
        )

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(wiki, installedApps: [wiki])

        #expect(Set(scan.leftovers.map { "\($0.kind.rawValue)/\($0.url.lastPathComponent)" }) == [
            "safariWebApps/\(identifier)", "preferences/\(identifier).plist",
        ])
        #expect(scan.leftovers.allSatisfy { $0.match.isRecommended })
    }

    @Test func aCopyMacOSKnowsElsewhereSharesTheAppsFiles() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Preferences/com.apple.CharacterPaletteIM.plist", bytes: 4096)
        let elsewhere = URL(filePath: "/System/Library/Input Methods/CharacterPalette.app")
        // Only an app Apple signed can claim Apple's files, and this copy stands in for one.
        let palette = InstalledApp(
            url: URL(filePath: "/Applications/CharacterPalette.app"),
            bundleIdentifier: "com.apple.CharacterPaletteIM",
            name: "Character Palette",
            teamIdentifier: "59GAB85EFG"
        )
        let listed = InstalledApp(
            url: elsewhere,
            bundleIdentifier: palette.bundleIdentifier,
            name: palette.name,
            isSystemProtected: true
        )
        let scanner = LeftoverScanner(environment: environment(in: directory))

        for installedApps in [[palette], [palette, listed]] {
            let scan = await scanner.scan(palette, installedApps: installedApps)
            let preferences = try #require(scan.leftovers.first { $0.kind == .preferences })
            #expect(
                preferences.match.otherCopies.map(PathPattern.comparablePath) == [
                    PathPattern.comparablePath(of: elsewhere)
                ]
            )
            #expect(!preferences.match.isRecommended)
        }
    }

    @Test func asksSpotlightForTheMakersAppsButNeverApples() {
        let makers = ["org.example.", "maccatalyst.org.example."]
        #expect(LeftoverScanner.makersPrefixes(of: "org.example.notes") == makers)
        #expect(LeftoverScanner.makersPrefixes(of: "maccatalyst.org.example.notes") == makers)
        #expect(LeftoverScanner.makersPrefixes(of: "com.apple.Safari").isEmpty)
        #expect(LeftoverScanner.makersPrefixes(of: "maccatalyst.com.apple.news").isEmpty)
        #expect(LeftoverScanner.makersPrefixes(of: "org.example").isEmpty)
    }

    /// An app inside the home's Library or the Mac's is part of another app, such as an agent kept in its maker's
    /// support folder or a build, so it keeps no file of an app it resembles. macOS's own Library is not one of them.
    @Test func anAppInALibraryFolderIsPartOfAnotherApp() {
        let mac = SearchEnvironment(homeDirectory: URL(filePath: "/Users/x"), rootDirectory: URL(filePath: "/"))

        #expect(!mac.keepsOnItsOwn(appAt: "/Users/x/Library/Application Support/Sketchpad/SketchpadAgent.app"))
        #expect(!mac.keepsOnItsOwn(appAt: "/Library/Application Support/Sketchpad/Updater.app"))
        #expect(mac.keepsOnItsOwn(appAt: "/Users/x/Downloads/Sketchpad Nightly.app"))
        #expect(mac.keepsOnItsOwn(appAt: "/Volumes/Disk/Sketchpad.app"))
        #expect(mac.keepsOnItsOwn(appAt: "/System/Library/Input Methods/CharacterPalette.app"))
        #expect(mac.keepsOnItsOwn(appAt: "/Users/x/Libraryish/Sketchpad.app"))
    }

    /// The guard, which reads every spelling of a path from the disk, is asked only about what the scan would take
    /// or walk into, and what it refuses stays out.
    @Test func asksTheGuardOnlyAboutWhatItWouldTakeOrWalkInto() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...200 {
            try directory.file("home/Library/Preferences/com.example.other\(index).plist", bytes: 1)
        }
        for index in 1...300 {
            try directory.file("home/Library/Caches/com.example.other/cache \(index).db", bytes: 1)
        }
        try directory.directory("home/Library/Caches/net.example.client")
        let asked = Mutex<[String]>([])
        let scanner = LeftoverScanner(
            environment: environment(in: directory),
            measure: { _ in FolderContents(size: 1, holdsRepository: false) },
            refuses: { path, home in
                asked.withLock { $0.append(URL(filePath: path).lastPathComponent) }
                return ProtectedData.refuses(path, home: home)
            }
        )
        let tunewell = tunewell

        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["net.example.client"])
        #expect(asked.withLock { $0.sorted() } == ["com.example.other", "net.example.client"])
    }

    @Test func findsMatchingItemsAcrossLocations() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Preferences/net.example.client.plist")
        try directory.file("home/Library/Caches/net.example.client/Data/cache.db", bytes: 64_000)
        try directory.directory("home/Library/Application Support/Tunewell")
        try directory.file("home/Library/Caches/com.example.other/cache.db")
        try directory.file("root/Library/LaunchAgents/net.example.webhelper.plist")
        try directory.directory("var/C/net.example.client")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })
        #expect(Set(found.keys) == [
            "home/Library/Preferences/net.example.client.plist",
            "home/Library/Caches/net.example.client",
            "home/Library/Application Support/Tunewell",
            "root/Library/LaunchAgents/net.example.webhelper.plist",
            "var/C/net.example.client",
        ])
        #expect(scan.leftovers.first?.url.lastPathComponent == "net.example.client")
        #expect(scan.leftovers.first?.kind == .caches)
        let launchAgent = try #require(found["root/Library/LaunchAgents/net.example.webhelper.plist"])
        #expect(launchAgent.match.reason == .vendorPrefix)
        #expect(!launchAgent.match.isRecommended)
        #expect(scan.unreadableLocations.isEmpty)
    }

    /// Apple names some folders after its apps rather than with `com.apple.`, such as `Application Support/Music`.
    /// The apps macOS ships are never in the list of installed apps, so the scan adds them as rivals.
    @Test func anAppMacOSShipsIsARivalForAFolderOfItsName() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Application Support/Music")
        let namesake = InstalledApp(url: URL(filePath: "/Applications/Music.app"), bundleIdentifier: "com.acme.music", name: "Music")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            namesake,
            installedApps: [namesake]
        )

        let folder = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Music" })
        #expect(folder.match.sharedWith == ["com.apple.Music"])
        #expect(!folder.match.isRecommended)
    }

    /// A folder that could not be measured in time is not an empty one. It may be a large folder with a
    /// repository inside, which is exactly the case the repository rule is for.
    @Test func aFolderThatCouldNotBeMeasuredIsShownAndNotSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Tunewell/checkout/.git/HEAD")
        try directory.file("home/Library/Caches/net.example.client/cache.db", bytes: 4_096)
        let slow = directory.url.appending(path: "home/Library/Application Support/Tunewell")

        let scanner = LeftoverScanner(environment: environment(in: directory)) { url in
            url.lastPathComponent == slow.lastPathComponent ? nil : await FileSize.contents(of: url)
        }
        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        let unmeasured = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Tunewell" })
        // Listed first, as every list does with a size it does not know: it is most likely the biggest.
        #expect(scan.leftovers.first?.url.lastPathComponent == "Tunewell", "the folder that ran out of time was listed last")
        #expect(scan.adding([]).leftovers.first?.url.lastPathComponent == "Tunewell")
        #expect(unmeasured.match.heldBack == .notMeasured)
        #expect(!unmeasured.match.isRecommended)
        #expect(!unmeasured.isMeasured)
        let measured = try #require(scan.leftovers.first { $0.url.lastPathComponent == "net.example.client" })
        #expect(measured.match.heldBack == nil)
        #expect(measured.match.isRecommended)
        #expect(measured.isMeasured)
    }

    /// The recent documents folder is a location of its own and also sits two levels inside Application Support,
    /// which is searched two levels deep. A file reached both ways is listed once: listed twice, it would be
    /// counted twice, and its second move would be reported as a failure.
    @Test func aFileReachedTwoWaysIsListedOnce() async throws {
        let directory = try TemporaryDirectory()
        let list = "home/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/net.example.client.sfl3"
        try directory.file(list)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let found = scan.leftovers.filter { $0.url.lastPathComponent == "net.example.client.sfl3" }
        #expect(found.count == 1, "listed \(found.count) times")
        #expect(found.first?.kind == .recentDocuments)
        #expect(found.first?.match.confidence == .certain, "the stronger of the two claims is the one kept")
    }

    /// A cask may write a folder's path with a trailing slash, while the scanner writes it without one. It is
    /// the same folder, and `adding(_:)` compares paths rather than URLs, so it stays one row.
    @Test func aPathACaskSpellsWithASlashIsNotASecondRow() {
        let match = LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: [])
        let found = Leftover(
            url: URL(filePath: "/Users/x/Library/Caches/net.example.client"),
            kind: .caches,
            match: match,
            size: 10,
            isMeasured: true,
            requiresPrivileges: false
        )
        let named = Leftover(
            url: URL(filePath: "/Users/x/Library/Caches/net.example.client/", directoryHint: .isDirectory),
            kind: .caches,
            match: LeftoverMatch(reason: .homebrewCask, confidence: .possible, sharedWith: []),
            size: 10,
            isMeasured: true,
            requiresPrivileges: false
        )

        let scan = LeftoverScan(leftovers: [found], unreadableLocations: []).adding([named])

        #expect(scan.leftovers.count == 1)
        #expect(scan.leftovers.first?.match.reason == .bundleIdentifier, "what the scanner already knew is kept")
    }

    /// A documentation browser keeps a folder for each product it documents, and an app that controls other
    /// apps keeps one for each of them. A folder named after this app inside another installed app's folder is
    /// that app's data about this one. The name alone is no reason to select it, but an identifier still is.
    @Test func aNameInsideAnotherInstalledAppsFolderIsNotEnough() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/SomeVendor/Tunewell/notes.db")
        try directory.file("home/Library/Application Support/SomeVendor/net.example.client/state.db")
        try directory.file("home/Library/Application Support/Nobody/Tunewell/notes.db")
        let other = InstalledApp(url: URL(filePath: "/Applications/SomeVendor.app"), bundleIdentifier: "com.somevendor.app", name: "SomeVendor")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell, other]
        )
        let byPath = Dictionary(
            uniqueKeysWithValues: scan.leftovers.map {
                ($0.url.path(percentEncoded: false).components(separatedBy: "Application Support/").last ?? "", $0)
            }
        )

        #expect(byPath["SomeVendor/Tunewell"]?.match.heldBack == .insideAnotherAppsFolder)
        #expect(byPath["SomeVendor/Tunewell"]?.match.isRecommended == false)
        #expect(byPath["SomeVendor/net.example.client"]?.match.isRecommended == true, "an identifier names the app wherever it sits")
        #expect(byPath["Nobody/Tunewell"]?.match.heldBack == .namedLikeTheApp, "a folder named for neither app nor maker")
    }

    /// A name found inside a folder counts only when every folder on the way is named for the app or its maker, by
    /// the maker's part of its identifier or the developer its signature names. Inside any other folder, such as
    /// macOS's own sync store or a command-line tool's settings, the name is all there is.
    @Test func aNameInsideAFolderOfNeitherTheAppNorItsMakerIsNotEnough() async throws {
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Hollow.app"),
            bundleIdentifier: "org.night-owl.hollow",
            name: "Hollow",
            developer: "Lantern Works, Inc."
        )
        let makers = ["Night Owl/Hollow", "night-owl/Hollow", "Lantern Works/Hollow", "Lantern.localized/Hollow"]
        let others = ["SyncServices/Hollow", "tool/telemetry/hollow"]
        let directory = try TemporaryDirectory()
        for folder in makers + others {
            try directory.file("home/Library/Application Support/\(folder)/state.db")
        }

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])

        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            ($0.url.path(percentEncoded: false).components(separatedBy: "Application Support/").last ?? "", $0)
        })
        for folder in makers {
            #expect(found[folder]?.match.isRecommended == true, "\(folder)")
        }
        for folder in others {
            #expect(found[folder]?.match.heldBack == .namedLikeTheApp, "\(folder)")
            #expect(found[folder]?.match.isRecommended == false, "\(folder)")
        }
    }

    /// Leaving a page cancels its scan, and a canceled scan starts no other measurement, so only those already under
    /// way can have begun. Otherwise, moving through a list of apps would leave a scan running for every app passed.
    @Test func aScanThatWasCanceledStopsMeasuring() async throws {
        let directory = try TemporaryDirectory()
        for index in 0..<40 {
            try directory.file("home/Library/Caches/net.example.client.part\(index)/cache.db")
        }
        let measured = Mutex(0)
        let scanner = LeftoverScanner(environment: environment(in: directory)) { _ in
            measured.withLock { $0 += 1 }
            // Holds the first measurement until the scan has been canceled.
            while !Task.isCancelled { await Task.yield() }
            return FolderContents(size: 1, holdsRepository: false)
        }

        let scan = Task { await scanner.scan(tunewell, installedApps: [tunewell]) }
        while measured.withLock({ $0 }) == 0 { await Task.yield() }
        scan.cancel()
        _ = await scan.value

        #expect(measured.withLock { $0 } <= LeftoverScanner.concurrentMeasurements, "it went on measuring after it was canceled")
    }

    /// An app can keep a whole photo, music, or video library beside its settings. `RemovalGuard` refuses to
    /// move a folder holding one, so the row says so from the start instead of failing at the move.
    @Test func aFolderThatHoldsALibraryIsShownAndLeftAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Tunewell/Libraries/Main.musiclibrary/Library.musicdb")
        try directory.file("home/Library/Caches/net.example.client/cache.db")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let support = try #require(scan.leftovers.first { $0.kind == .applicationSupport })
        #expect(support.match.heldBack == .holdsALibrary)
        #expect(!support.match.isRecommended)
        #expect(scan.leftovers.first { $0.kind == .caches }?.match.isRecommended == true)
    }

    /// A sandboxed app keeps what its user made in `Data/Documents`, inside the container an uninstall lists.
    @Test func aContainerThatHoldsDocumentsIsShownAndLeftAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Containers/net.example.client/Data/Documents/playlist.txt")
        try directory.file("home/Library/Group Containers/ABCDE12345.net.example.client/cache.db")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let container = try #require(scan.leftovers.first { $0.kind == .containers })
        #expect(container.match.heldBack == .holdsDocuments)
        #expect(!container.match.isRecommended)

        try FileManager.default.removeItem(at: container.url.appending(path: "Data/Documents/playlist.txt"))
        let emptied = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )
        #expect(try #require(emptied.leftovers.first { $0.kind == .containers }).match.isRecommended)
    }

    /// macOS keeps privileged helpers only in the Mac's Library, so the home's folder by that name is searched.
    @Test func searchesAFolderTheHomesLibraryHasOnlyByAnotherLibrarysName() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/PrivilegedHelperTools/net.example.client.helper")

        let scanner = LeftoverScanner(environment: environment(in: directory))

        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["net.example.client.helper"])
    }

    @Test func eachLibrarySkipsOnlyWhatItSearchesItself() throws {
        let directory = try TemporaryDirectory()
        let environment = environment(in: directory)
        let libraries = environment.locations.filter { $0.kind == .library }
        let home = try #require(libraries.first { $0.url.path(percentEncoded: false).contains("/home/") })
        let mac = try #require(libraries.first { $0.url.path(percentEncoded: false).contains("/root/") })

        #expect(!home.considers(fileName: "Preferences") && !mac.considers(fileName: "Preferences"))
        #expect(!home.considers(fileName: "Containers") && mac.considers(fileName: "Containers"))
        #expect(!home.considers(fileName: "Frameworks") && mac.considers(fileName: "Frameworks"))
        #expect(home.considers(fileName: "PrivilegedHelperTools") && !mac.considers(fileName: "PrivilegedHelperTools"))
        #expect(home.considers(fileName: "Extensions") && !mac.considers(fileName: "Extensions"))
        #expect(!home.considers(fileName: "Audio") && !mac.considers(fileName: "Audio"))
    }

    @Test func aCacheThatKeepsAnEditorsLocalHistoryIsShownAndLeftAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/net.example.client/LocalHistory/changes.storageData")
        try directory.file("home/Library/Caches/net.example.client/index/files.dat")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let cache = try #require(scan.leftovers.first { $0.kind == .caches })
        #expect(cache.match.heldBack == .holdsWorkKeptInACache)
        #expect(cache.match.heldBack?.cannotBeMoved == true)
        #expect(!cache.match.isRecommended)
    }

    @Test(.permissionsHold) func reportsUnreadableLocations() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Logs/Tunewell/log.txt")
        try directory.setPermissions(0o000, of: "home/Library/Logs")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Logs") }

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        #expect(scan.leftovers.isEmpty)
        #expect(scan.unreadableLocations.map(\.kind) == [.logs])
        #expect(!scan.needsFullDiskAccess, "Full Disk Access does not open a folder closed by ordinary permissions")
    }

    /// A vendor's folder the deep search cannot look into may hold the app's files, so the scan says it could not
    /// read it rather than passing over it as if it held nothing.
    @Test(.permissionsHold) func reportsAFolderTheDeepSearchCannotLookInto() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Vendor/Tunewell/state.db")
        try directory.setPermissions(0o000, of: "home/Library/Application Support/Vendor")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Application Support/Vendor") }

        let scanner = LeftoverScanner(environment: environment(in: directory))
        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        #expect(scan.unreadableLocations.map(\.url.lastPathComponent) == ["Vendor"])
        #expect(scan.unreadableLocations.map(\.kind) == [.applicationSupport])
        #expect(!scan.needsFullDiskAccess)
    }

    /// A folder of Apple's own the deep search cannot look into, such as macOS's icon store in the Caches, holds none
    /// of another app's files, so saying so on every app's page would only be noise.
    @Test(.permissionsHold) func leavesApplesOwnFoldersItCannotReadUnsaid() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.apple.iconservices.store/cache.db")
        try directory.setPermissions(0o000, of: "home/Library/Caches/com.apple.iconservices.store")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Caches/com.apple.iconservices.store") }

        let scanner = LeftoverScanner(environment: environment(in: directory))
        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        #expect(scan.unreadableLocations.isEmpty)
    }

    @Test(.permissionsHold) func flagsItemsInReadOnlyLocationsAsRequiringPrivileges() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Library/LaunchDaemons/net.example.client.helper.plist")
        try directory.file("home/Library/Preferences/net.example.client.plist")
        try directory.setPermissions(0o555, of: "root/Library/LaunchDaemons")
        defer { try? directory.setPermissions(0o755, of: "root/Library/LaunchDaemons") }

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let privileges = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.kind, $0.requiresPrivileges) })
        #expect(privileges == [.launchDaemons: true, .preferences: false])
    }

    /// Two real cases: a crash reporter keeps a folder for each app, and macOS keeps a help cache for each
    /// app. The inner folder carries the app's identifier, but the folder around it belongs to someone else.
    @Test func findsFilesBuriedInSomebodyElsesFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.plausiblelabs.crashreporter.data/net.example.client/report.plist")
        try directory.file("home/Library/Caches/com.apple.helpd/Generated/net.example.client.help-1.0/index.html")
        try directory.file("home/Library/Application Support/SomeVendor/Tunewell/state.json")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })
        #expect(Set(found.keys) == [
            "home/Library/Caches/com.plausiblelabs.crashreporter.data/net.example.client",
            "home/Library/Caches/com.apple.helpd/Generated/net.example.client.help-1.0",
            "home/Library/Application Support/SomeVendor/Tunewell",
        ])
        #expect(found["home/Library/Caches/com.plausiblelabs.crashreporter.data/net.example.client"]?.match.reason == .bundleIdentifier)
        #expect(found["home/Library/Caches/com.apple.helpd/Generated/net.example.client.help-1.0"]?.match.reason == .bundleIdentifierPrefix)
    }

    /// The scan looks inside a limited number of other folders. At the limit it reports the location, and the
    /// folders it looked into are chosen in name order, not in the order the disk listed them.
    @Test func saysWhenItStoppedLookingInsideFolders() async throws {
        let directory = try TemporaryDirectory()
        for index in 0..<6 {
            try directory.directory("home/Library/Application Support/Aardvark \(index)")
        }
        try directory.file("home/Library/Application Support/SomeVendor/Tunewell/state.json")
        let scanner = LeftoverScanner(
            environment: environment(in: directory),
            measure: LeftoverScanner.walk,
            nestedFolderLimit: 5
        )

        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        #expect(scan.leftovers.isEmpty, "the folder past the limit was looked into")
        #expect(scan.cutShortLocations.map(\.kind) == [.applicationSupport])

        let whole = await LeftoverScanner(environment: environment(in: directory), measure: LeftoverScanner.walk).scan(
            tunewell,
            installedApps: [tunewell]
        )
        #expect(whole.leftovers.map(\.url.lastPathComponent) == ["Tunewell"])
        #expect(whole.cutShortLocations.isEmpty)
    }

    /// Inside a folder that is not the app's, only a match strong enough to name the app on its own is taken. A
    /// shared vendor prefix, or a name the file only starts with, is not enough there.
    @Test func leavesGuessesInsideSomebodyElsesFolderAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/SomeVendor/net.example.notthisapp.plist")
        try directory.file("home/Library/Caches/SomeVendor/Tunewell Installer Log.txt")
        try directory.file("home/Library/Caches/SomeVendor/Tunewell")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["Tunewell"])
    }

    /// A folder that is already the app's own is reported whole; its contents are not listed again.
    @Test func doesNotLookInsideAFolderItAlreadyFound() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/net.example.client/net.example.client.db")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["net.example.client"])
    }

    /// A container belongs entirely to the app it is named for, so the scan never looks inside another app's.
    @Test func staysOutOfOtherAppsContainers() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Containers/com.example.other/Data/net.example.client.plist")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        #expect(scan.leftovers.isEmpty)
    }

    /// Apps installed for every account on the Mac can keep their files in `/Users/Shared`.
    @Test func findsWhatAnAppLeftInTheSharedFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Users/Shared/Tunewell/library.db", bytes: 4_000)
        try directory.file("root/Users/Shared/Something Else/notes.txt")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["Tunewell"])
        #expect(scan.leftovers.first?.kind == .sharedFolder)
        #expect(scan.leftovers.first?.match.reason == .name)
    }

    /// Some apps keep hidden settings at the top of the home folder, and tools that follow the XDG convention
    /// use `.config`. A few apps keep a plain folder there, which is shown but never selected. Nothing inside
    /// `Documents` is looked at.
    @Test func findsWhatAnAppHidesInTheHomeFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/.tunewell/state.json")
        try directory.file("home/.config/tunewell/config.toml")
        try directory.file("home/.ssh/id_ed25519")
        try directory.file("home/Tunewell/my own notes.txt")
        try directory.file("home/Documents/Tunewell")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(
            scan.leftovers.map { (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(Set(found.keys) == ["home/.tunewell", "home/.config/tunewell", "home/Tunewell"])
        #expect(found["home/.tunewell"]?.kind == .hiddenHomeFiles)
        #expect(found["home/Tunewell"]?.kind == .homeFolder)
        #expect(found["home/Tunewell"]?.match.isRecommended == false)
    }

    /// A folder at the top of the home folder whose name only begins with the app's, such as the library of books
    /// an ebook app makes there, is the person's own work and is never selected.
    @Test func aFolderNamedAfterTheAppAtTheTopOfTheHomeIsNeverSelected() async throws {
        let app = InstalledApp(url: URL(filePath: "/Applications/Folio.app"), bundleIdentifier: "org.example.folio", name: "Folio")
        let directory = try TemporaryDirectory()
        try directory.file("home/Folio Library/metadata.db", bytes: 4_096)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])

        for leftover in scan.leftovers where leftover.url.path(percentEncoded: false).contains("Folio Library") {
            #expect(!leftover.match.isRecommended, "\(leftover.match.reason) selected the person's own library")
        }
    }

    /// A bundle writes its own identifier, and one that is a single word proves no more than a name. So it is held
    /// back where a name is: here an app says its identifier is `notes`, and `~/.notes` holds another tool's work.
    /// The same goes inside a folder of another installed app.
    @Test func aOneWordIdentifierIsHeldBackWhereANameIs() async throws {
        let app = InstalledApp(url: URL(filePath: "/Applications/Jotter.app"), bundleIdentifier: "notes", name: "Jotter")
        let other = InstalledApp(url: URL(filePath: "/Applications/Vendor.app"), bundleIdentifier: "com.vendor.app", name: "Vendor")
        let directory = try TemporaryDirectory()
        try directory.file("home/.notes/journal/2026.md", bytes: 4_096)
        try directory.file("home/Library/Application Support/Vendor/notes/state.json")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app, other])

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })
        let hidden = try #require(found["home/.notes"])
        #expect(!hidden.match.isRecommended, "a hidden home folder was selected on a one-word identifier")
        #expect(hidden.match.heldBack == .namedLikeTheApp)
        let insideAnother = try #require(found["home/Library/Application Support/Vendor/notes"])
        #expect(!insideAnother.match.isRecommended, "another app's folder was taken apart on a one-word identifier")
        #expect(insideAnother.match.heldBack == .insideAnotherAppsFolder)
    }

    /// A hidden `~/.jotter` can belong to a command-line tool of the same name, holding work that exists nowhere
    /// else, while the Jotter app shares only the name. A name alone is not enough to select a hidden home folder.
    ///
    /// Both parts matter: the folder is shown but not selected, and a nested entry such as `~/.config/jotter` is
    /// still listed. So the scanner decides this, not the matcher: `nested(in:)` takes only matches that are
    /// `likely` or better, and weaker evidence from the matcher would drop nested entries from the list entirely.
    @Test func aHiddenHomeEntryOnANameIsShownAndNeverSelected() async throws {
        let jotter = InstalledApp(
            url: URL(filePath: "/Applications/Jotter.app"),
            bundleIdentifier: "com.example.jotter",
            name: "Jotter"
        )
        let directory = try TemporaryDirectory()
        try directory.file("home/.jotter/projects/session.jsonl", bytes: 4_096)
        try directory.file("home/.config/jotter/settings.json")
        try directory.directory("home/.com.example.jotter")
        try directory.directory("home/Library/Application Support/Jotter")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(jotter, installedApps: [jotter])

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })

        let hidden = try #require(found["home/.jotter"], "the folder was hidden from the user instead of shown")
        #expect(hidden.match.reason == .name)
        #expect(!hidden.match.isRecommended, "a hidden home folder was selected on the app's name alone")
        // The row has to be able to say why it is not selected, or it reads as an oversight.
        #expect(hidden.match.heldBack == .namedLikeTheApp)

        let nested = try #require(found["home/.config/jotter"], "a nested hidden entry was dropped instead of shown")
        #expect(nested.match.reason == .name)
        #expect(!nested.match.isRecommended)

        // A match on the identifier is still selected in the home folder, and one on the name in Application Support.
        #expect(found["home/.com.example.jotter"]?.match.isRecommended == true)
        #expect(found["home/Library/Application Support/Jotter"]?.match.isRecommended == true)
    }

    /// `~/.local` and `~/.config` are shared by many command line tools, and `RemovalGuard` refuses to move them.
    /// An app called Local would claim `~/.local` by its name, so the folder itself is never offered, but what
    /// is inside it is still looked at and listed.
    @Test func aFolderTheWholeMacSharesIsNotOfferedButIsStillLookedInside() async throws {
        let local = InstalledApp(
            url: URL(filePath: "/Applications/Local.app"),
            bundleIdentifier: "com.wpengine.local",
            name: "Local"
        )
        let directory = try TemporaryDirectory()
        try directory.file("home/.local/share/local/state.json")
        try directory.file("home/.config/local/settings.json")
        try directory.file("home/.local/bin/python3.13")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(local, installedApps: [local])

        let root = directory.url.path(percentEncoded: false)
        let paths = Set(scan.leftovers.map { String($0.url.path(percentEncoded: false).dropFirst(root.count)) })
        #expect(!paths.contains("home/.local"), "a folder every tool on the Mac shares was offered for removal")
        #expect(paths == ["home/.local/share/local", "home/.config/local"])
    }


    /// A folder with a repository inside holds more than the app's own state. It is still listed as the app's,
    /// but not selected, because work that is not committed or not pushed exists nowhere else.
    @Test func aLeftoverHoldingARepositoryIsShownAndNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Tunewell/settings.json")
        try directory.file("home/Library/Application Support/Tunewell/workspaces/a/b/project/.git/HEAD")
        try directory.file("home/Library/Caches/net.example.client/cache.db", bytes: 64_000)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })
        let support = try #require(found["home/Library/Application Support/Tunewell"], "the folder disappeared instead of being shown")
        #expect(support.match.reason == .name)
        #expect(!support.match.isRecommended, "a folder holding a checkout was selected")
        #expect(support.match.heldBack == .holdsRepository, "the row could not say why it was left alone")
        // A folder beside it, with no repository in it, is untouched by the rule.
        #expect(found["home/Library/Caches/net.example.client"]?.match.isRecommended == true)
        #expect(found["home/Library/Caches/net.example.client"]?.match.heldBack == nil)
    }

    /// A folder macOS will not open would read as empty, and an empty folder of the app's own would be selected.
    /// From macOS 27, access to another team's container is denied outright rather than prompted for.
    @Test(.permissionsHold) func aLeftoverThatCannotBeReadIsNeverSelectedAndHasNoSize() async throws {
        let directory = try TemporaryDirectory()
        let container = try directory.directory("home/Library/Containers/net.example.client")
        try directory.file("home/Library/Containers/net.example.client/Data/Library/Caches/blob", bytes: 64_000)
        try directory.setPermissions(0o000, of: container)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: container.path(percentEncoded: false)
            )
        }

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )
        let found = try #require(scan.leftovers.first { $0.url.lastPathComponent == "net.example.client" })

        #expect(found.match.heldBack == .couldNotBeRead, "a folder nothing could be read from was taken for an empty one")
        #expect(!found.match.isRecommended)
        #expect(!found.isMeasured)
    }

    /// A folder inside the leftover that macOS will not open may hold what nothing brings back, as a helper's own
    /// `Private` folder with a wallet in it, so the leftover is not read to the end and is never selected.
    @Test(.permissionsHold) func aLeftoverNotReadToTheEndIsNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/net.example.client/settings.plist", bytes: 4_096)
        try directory.file("home/Library/Application Support/net.example.client/Private/wallet.dat", bytes: 4_096)
        try directory.setPermissions(0, of: "home/Library/Application Support/net.example.client/Private")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Application Support/net.example.client/Private") }

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )
        let found = try #require(scan.leftovers.first { $0.url.path(percentEncoded: false).hasSuffix("Application Support/net.example.client") })

        #expect(found.match.heldBack == .couldNotBeRead, "a folder read only in part was taken for all it holds")
        #expect(!found.match.isRecommended)
        #expect(!found.isMeasured)
    }

    /// Something excluded inside only leaves a folder unselected, so it never takes the place of a reason that blocks
    /// the move: the row still says the folder cannot be moved at all.
    @Test func anExclusionInsideNeverHidesAReasonThatBlocksTheMove() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Tunewell/Libraries/Main.musiclibrary/Library.musicdb")
        try directory.file("home/Library/Application Support/Tunewell/logs/today.log")
        let folder = directory.url.appending(path: "home/Library/Application Support/Tunewell")
        let exclusions = Exclusions(paths: [folder.appending(path: "logs")])

        let scanner = LeftoverScanner(environment: environment(in: directory), exclusions: exclusions)
        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        let found = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Tunewell" })
        #expect(found.match.heldBack == .holdsALibrary)
        #expect(found.match.heldBack?.cannotBeMoved == true)
    }

    /// An exclusion inside replaces `notMeasured` as the reason, but the folder's size stays unknown, not zero.
    @Test func aFolderHoldingAnExclusionKeepsASizeNobodyKnows() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Tunewell/kept/notes.txt")
        let folder = directory.url.appending(path: "home/Library/Application Support/Tunewell")
        let exclusions = Exclusions(paths: [folder.appending(path: "kept")])

        let scanner = LeftoverScanner(environment: environment(in: directory), exclusions: exclusions) { url in
            url.lastPathComponent == folder.lastPathComponent ? nil : await FileSize.contents(of: url)
        }
        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        let found = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Tunewell" })
        #expect(found.match.heldBack == .holdsAnExclusion)
        #expect(found.match.heldBack?.cannotBeMoved == true, "the guard refuses a folder holding an exclusion")
        #expect(!found.isMeasured, "a folder nobody measured was given a size of zero")
    }

    @Test func measuresNothingExcluded() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/net.example.client/cache.db")
        try directory.file("home/Library/Application Support/Vendor/Tunewell/state.db")
        try directory.file("home/Library/Application Support/Tunewell/settings.json")
        let library = directory.url.appending(path: "home/Library")
        let exclusions = Exclusions(paths: [
            library.appending(path: "Caches/net.example.client"), library.appending(path: "Application Support/Vendor"),
        ])
        let measured = Mutex<Set<String>>([])

        let scanner = LeftoverScanner(environment: environment(in: directory), exclusions: exclusions) { url in
            measured.withLock { _ = $0.insert(url.path(percentEncoded: false)) }
            return FolderContents(size: 1, holdsRepository: false)
        }
        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        let kept = library.appending(path: "Application Support/Tunewell").path(percentEncoded: false)
        #expect(measured.withLock { $0 } == [kept])
        #expect(scan.leftovers.map { $0.url.path(percentEncoded: false) } == [kept])
    }

    /// A Homebrew cask can name a cryptocurrency app's whole data folder, which is where its private keys are:
    /// Litecoin Core's `zap trash:` does exactly that.
    @Test func aLeftoverHoldingAWalletIsShownAndNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        let coin = InstalledApp(
            url: URL(filePath: "/Applications/Litecoin-Qt.app"),
            bundleIdentifier: "org.litecoin.Litecoin-Qt",
            name: "Litecoin-Qt"
        )
        try directory.file("home/Library/Application Support/Litecoin-Qt/wallet.dat", bytes: 64)
        try directory.file("home/Library/Application Support/Litecoin-Qt/blocks/blk0000.dat", bytes: 64_000)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(coin, installedApps: [coin])
        let folder = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Litecoin-Qt" })

        #expect(!folder.match.isRecommended, "a folder holding a wallet was selected")
        #expect(folder.match.heldBack == .holdsAWallet)
    }

    /// A folder that holds a wallet Peel protects is listed, and cannot be selected: `RemovalGuard` refuses to
    /// move it, so offering it would only end in a refusal.
    @Test func aLeftoverHoldingAProtectedWalletCannotBeSelected() async throws {
        let directory = try TemporaryDirectory()
        let coin = InstalledApp(url: URL(filePath: "/Applications/Litecoin.app"), bundleIdentifier: "org.litecoin.Litecoin", name: "Litecoin")
        try directory.file("home/Library/Application Support/Litecoin/wallets/wallet.dat", bytes: 64)
        try directory.file("home/Library/Application Support/Litecoin/blocks/blk0000.dat", bytes: 64_000)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(coin, installedApps: [coin])
        let folder = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Litecoin" })

        #expect(folder.match.heldBack == .holdsKeys)
        #expect(folder.match.heldBack?.cannotBeMoved == true)
    }

    /// Where a key Peel protects lies is known from the path alone, so a folder macOS will not let Peel read, but
    /// that holds such a key, is shown as one that cannot be selected, not merely as one that was not read.
    @Test func aFolderThatCannotBeReadButHoldsAProtectedKeyCannotBeSelected() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("home/Library/Application Support/Litecoin")

        let leftover = await LeftoverScanner.leftover(
            at: folder,
            kind: .applicationSupport,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: []),
            parent: ParentAccess(folder.deletingLastPathComponent()),
            home: directory.url.appending(path: "home").path(percentEncoded: false),
            measure: { _ in FolderContents(size: 0, holdsRepository: false, couldNotBeRead: true) }
        )

        #expect(leftover.match.heldBack == .holdsKeys)
    }

    /// A reason the guard will refuse the move for comes before the walk's, so a container with documents inside,
    /// or a folder around a library, reads as one that cannot be selected even when macOS would not let Peel read
    /// the folder.
    @Test func whatTheGuardWillRefuseComesBeforeAFolderThatCouldNotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let container = try directory.directory("home/Library/Containers/com.example.notes")
        try directory.file("home/Library/Containers/com.example.notes/Data/Documents/novel.txt")
        let photos = try directory.directory("home/Library/Application Support/Example")
        try directory.file("home/Library/Application Support/Example/2024/Trip.photoslibrary/database/Photos.sqlite")
        let unread: LeftoverScanner.Measure = { _ in
            FolderContents(size: 0, holdsRepository: false, couldNotBeRead: true)
        }
        func leftover(_ url: URL, _ kind: SearchLocation.Kind) async -> Leftover {
            await LeftoverScanner.leftover(
                at: url,
                kind: kind,
                match: LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: []),
                parent: ParentAccess(url.deletingLastPathComponent()),
                home: directory.url.appending(path: "home").path(percentEncoded: false),
                measure: unread
            )
        }

        #expect(await leftover(container, .containers).match.heldBack == .holdsDocuments)
        #expect(await leftover(photos, .applicationSupport).match.heldBack == .holdsALibrary)
    }

    /// A browser's folder that holds a profile with a wallet extension cannot be selected either.
    @Test func aBrowsersFolderHoldingAWalletCannotBeSelected() async throws {
        let directory = try TemporaryDirectory()
        let opera = InstalledApp(url: URL(filePath: "/Applications/Opera.app"), bundleIdentifier: "com.operasoftware.Opera", name: "Opera")
        try directory.file("home/Library/Application Support/com.operasoftware.Opera/Local Extension Settings/\(WalletIDs.metaMask)/000003.log")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(opera, installedApps: [opera])
        let folder = try #require(scan.leftovers.first { $0.url.lastPathComponent == "com.operasoftware.Opera" })

        #expect(folder.match.heldBack == .holdsKeys)
    }

    /// A cask can name a folder in another case than the disk spells it. It is the folder the scan already found,
    /// held back as a name at the top of a Library is, so it is listed once, as the scan found it.
    @Test func aCaskPathInAnotherCaseIsTheFolderTheScanFound() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Tunewell/settings.db", bytes: 100)
        let tunewell = InstalledApp(url: URL(filePath: "/Applications/Tunewell.app"), bundleIdentifier: "net.example.tunewell", name: "Tunewell")
        let cask = HomebrewPackage(name: "tunewell", kind: .cask, appNames: ["Tunewell.app"], leftoverPatterns: ["~/Library/TUNEWELL"])
        let environment = environment(in: directory)
        let scan = await LeftoverScanner(environment: environment).scan(tunewell, installedApps: [tunewell])
        let evidence = try #require(
            CaskEvidence.evidence(for: tunewell, casks: [cask], home: environment.homeDirectory)
        )
        let fromTheCask = await Uninstallation.caskLeftovers(
            evidence,
            app: tunewell,
            exclusions: .none,
            matcher: LeftoverMatcher(app: tunewell, installedApps: [tunewell]),
            environment: environment
        )

        let merged = scan.adding(fromTheCask)

        #expect(merged.leftovers.map(\.url.lastPathComponent) == ["Tunewell"])
        #expect(merged.leftovers.first?.match.heldBack == .namedLikeTheApp)
    }

    /// Plug-ins that declare the app's identifier are found in the user's Library and the system's, including inside
    /// a vendor's own folder.
    @Test func findsThePlugInsAnAppInstalled() async throws {
        let directory = try TemporaryDirectory()
        let massive = InstalledApp(
            url: URL(filePath: "/Applications/Massive.app"),
            bundleIdentifier: "com.native-instruments.massive",
            name: "Massive"
        )
        try directory.file("home/Library/Audio/Plug-Ins/VST3/Massive.vst3/Contents/Info.plist", contents: plist("com.native-instruments.massive.vst3"))
        try directory.file("root/Library/Audio/Plug-Ins/Components/Massive.component/Contents/Info.plist", contents: plist("com.native-instruments.massive.au"))
        try directory.file("root/Library/Audio/Plug-Ins/VST/Native Instruments/Massive.vst/Contents/Info.plist", contents: plist("com.native-instruments.massive.vst"))
        try directory.file("root/Library/QuickLook/Somebody Else.qlgenerator/Contents/Info.plist", bytes: 512)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            massive,
            installedApps: [massive]
        )

        let root = directory.url.path(percentEncoded: false)
        let found = Set(scan.leftovers.map { String($0.url.path(percentEncoded: false).dropFirst(root.count)) })
        #expect(found == [
            "home/Library/Audio/Plug-Ins/VST3/Massive.vst3",
            "root/Library/Audio/Plug-Ins/Components/Massive.component",
            "root/Library/Audio/Plug-Ins/VST/Native Instruments/Massive.vst",
        ])
        #expect(scan.leftovers.allSatisfy { $0.kind == .plugIns })
    }

    @Test func findsTheAppsMailBundle() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Mailer.app"), bundleIdentifier: "org.example.mailer", name: "Mailer"
        )
        try directory.file(
            "home/Library/Mail/Bundles/Mailer.mailbundle/Contents/Info.plist", contents: plist("org.example.mailer.bundle")
        )
        try directory.file("home/Library/Caches/org.example.mailer/blob")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])

        #expect(Set(scan.leftovers.map(\.url.lastPathComponent)) == ["Mailer.mailbundle", "org.example.mailer"])
        #expect(scan.leftovers.first { $0.url.lastPathComponent == "Mailer.mailbundle" }?.match.isRecommended == true)
    }

    /// A plug-in is named for what it does, so when its name matches nothing, the identifier in its `Info.plist`
    /// is used instead. A match on the maker's prefix is only a guess, so the row is shown but never selected.
    @Test func readsThePlugInsOwnIdentifierWhenItsNameSaysNothing() async throws {
        let directory = try TemporaryDirectory()
        let central = InstalledApp(
            url: URL(filePath: "/Applications/Waves Central.app"),
            bundleIdentifier: "com.waves.wavescentral",
            name: "Waves Central"
        )
        try directory.file("root/Library/Audio/Plug-Ins/VST3/Q10.vst3/Contents/Info.plist", contents: plist("com.waves.Q10"))
        try directory.file("root/Library/Audio/Plug-Ins/VST3/Pro-Q.vst3/Contents/Info.plist", contents: plist("com.fabfilter.proq"))

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            central,
            installedApps: [central]
        )

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["Q10.vst3"])
        #expect(scan.leftovers.first?.match.reason == .vendorPrefix)
        #expect(scan.leftovers.first?.match.confidence == .possible)
        #expect(scan.leftovers.first?.match.isRecommended == false)
    }

    /// Another maker's plug-in can do what the app is called: the identifier it declares is not the app's, so its
    /// name makes it only possible, and inside a vendor's folder, where only a strong claim is taken, it is not listed.
    @Test func anotherMakersPlugInWithTheAppsNameIsNotSelected() async throws {
        let directory = try TemporaryDirectory()
        let compressor = InstalledApp(
            url: URL(filePath: "/Applications/Compressor.app"),
            bundleIdentifier: "net.example.compressor",
            name: "Compressor"
        )
        let plugIns = "root/Library/Audio/Plug-Ins"
        try directory.file("\(plugIns)/Components/Compressor.component/Contents/Info.plist", contents: plist("org.example.dynamics.compressor"))
        try directory.file("\(plugIns)/VST3/Dynamics/Compressor.vst3/Contents/Info.plist", contents: plist("org.example.dynamics.compressor"))
        try directory.file("\(plugIns)/VST3/Compressor.vst3/Contents/Info.plist", contents: plist("net.example.compressor.vst3"))

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            compressor,
            installedApps: [compressor]
        )

        let folder = directory.url.appending(path: plugIns).path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(folder.count + 1)), $0.match)
        })
        #expect(found.keys.sorted() == ["Components/Compressor.component", "VST3/Compressor.vst3"])
        #expect(found["Components/Compressor.component"]?.confidence == .possible)
        #expect(found["Components/Compressor.component"]?.isRecommended == false)
        #expect(found["VST3/Compressor.vst3"]?.reason == .bundleIdentifierPrefix)
        #expect(found["VST3/Compressor.vst3"]?.isRecommended == true)
    }

    /// A plug-in is claimed through the identifier it declares when that says more than its name, which may only
    /// start with the app's or say nothing of it, inside a vendor's folder as well.
    @Test func aPlugInsIdentifierOutweighsAWeakerName() async throws {
        let directory = try TemporaryDirectory()
        let tunewell = InstalledApp(
            url: URL(filePath: "/Applications/Tunewell.app"),
            bundleIdentifier: "net.example.tunewell",
            name: "Tunewell"
        )
        let plugIns = "root/Library/Audio/Plug-Ins"
        try directory.file("\(plugIns)/Components/Tunewell Reverb.component/Contents/Info.plist", contents: plist("net.example.tunewell.reverb"))
        try directory.file("\(plugIns)/VST3/Example Audio/Space.vst3/Contents/Info.plist", contents: plist("net.example.tunewell.space"))

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        #expect(Set(scan.leftovers.map(\.url.lastPathComponent)) == ["Tunewell Reverb.component", "Space.vst3"])
        #expect(scan.leftovers.allSatisfy { $0.match.reason == .bundleIdentifierPrefix && $0.match.isRecommended })
    }

    /// A framework in `~/Library/Frameworks` is named for what it is, so the identifier in its bundle says whose it
    /// is. The app's name alone, backed by no identifier, is only a guess.
    @Test func findsTheAppsFrameworksByTheIdentifierTheyDeclare() async throws {
        let directory = try TemporaryDirectory()
        let tunewell = InstalledApp(
            url: URL(filePath: "/Applications/Tunewell.app"),
            bundleIdentifier: "net.example.tunewell",
            name: "Tunewell"
        )
        for (name, identifier) in [
            ("TunewellKit", "net.example.tunewell.kit"), ("Tunewell", "org.example.other.tunewell"),
            ("Updates", "org.example.updates"),
        ] {
            let framework = "home/Library/Frameworks/\(name).framework"
            try directory.file("\(framework)/Versions/A/Resources/Info.plist", contents: plist(identifier))
            try FileManager.default.createSymbolicLink(
                atPath: directory.url.appending(path: "\(framework)/Versions/Current").path(percentEncoded: false),
                withDestinationPath: "A"
            )
            try FileManager.default.createSymbolicLink(
                atPath: directory.url.appending(path: "\(framework)/Resources").path(percentEncoded: false),
                withDestinationPath: "Versions/Current/Resources"
            )
        }

        let scanner = LeftoverScanner(environment: environment(in: directory))
        let scan = await scanner.scan(tunewell, installedApps: [tunewell])
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.url.lastPathComponent, $0.match) })

        #expect(Set(found.keys) == ["TunewellKit.framework", "Tunewell.framework"])
        #expect(found["TunewellKit.framework"]?.reason == .bundleIdentifierPrefix)
        #expect(found["TunewellKit.framework"]?.isRecommended == true)
        #expect(found["Tunewell.framework"]?.confidence == .possible)
        #expect(found["Tunewell.framework"]?.isRecommended == false)
        #expect(scan.leftovers.allSatisfy { $0.kind == .frameworks })
    }

    @Test func filesOfAnAppPeelSawGoAreNotTakenForAnAppWhoseIdentifierBeginsTheirs() async throws {
        let directory = try TemporaryDirectory()
        let environment = environment(in: directory)
        try directory.file("home/Library/Caches/org.example.solo.nightly/cache.db")
        try directory.file("home/Library/Caches/org.example.solo.helper/cache.db")
        let solo = InstalledApp(url: URL(filePath: "/Applications/Solo.app"), bundleIdentifier: "org.example.solo", name: "Solo")
        let nightly = InstalledApp(
            url: directory.url.appending(path: "Solo Nightly.app"), bundleIdentifier: "org.example.solo.nightly", name: "Solo Nightly"
        )
        await AppMemory(url: AppMemory.url(inHome: environment.homeDirectory)).remember([nightly])

        let scan = await LeftoverScanner(environment: environment).scan(solo, installedApps: [solo])
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.url.lastPathComponent, $0.match) })

        #expect(found["org.example.solo.nightly"]?.sharedWith == ["org.example.solo.nightly"])
        #expect(found["org.example.solo.helper"]?.isRecommended == true)
    }

    /// A launchd job is named by whoever wrote it, so a job whose program sits inside the app is the app's,
    /// whatever its file is called. That match is certain and outranks a weaker match on the file name.
    @Test func findsAJobByTheProgramItRuns() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/LaunchAgents/com.acmesoft.updater.plist", contents: job(program: "/Applications/Tunewell.app/Contents/MacOS/Updater"))
        try directory.file("home/Library/LaunchAgents/net.example.nagger.plist", contents: job(program: "/Applications/Tunewell.app/Contents/Helpers/Nagger"))
        try directory.file("home/Library/LaunchAgents/com.elsewhere.agent.plist", contents: job(program: "/Applications/Other.app/Contents/MacOS/Agent"))
        try directory.file("home/Library/LaunchAgents/com.relative.agent.plist", contents: job(program: "sleep"))

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.url.lastPathComponent, $0.match) })

        #expect(Set(found.keys) == ["com.acmesoft.updater.plist", "net.example.nagger.plist"])
        #expect(found["com.acmesoft.updater.plist"]?.reason == .launchdJob)
        #expect(found["com.acmesoft.updater.plist"]?.confidence == .certain)
        #expect(found["com.acmesoft.updater.plist"]?.isRecommended == true)
        // By its name alone it would be only a vendor prefix match; what it runs settles it.
        #expect(found["net.example.nagger.plist"]?.reason == .launchdJob)
    }

    /// A link in `/usr/local/bin` or `/usr/local/sbin` is named for the tool it runs, such as `docker` or `code`,
    /// which says nothing about whose it is. Where it leads does.
    @Test func findsALinkToAToolInsideTheApp() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: directory.url.appending(path: "root/Applications/Tunewell.app", directoryHint: .isDirectory),
            bundleIdentifier: "net.example.client",
            name: "Tunewell"
        )
        try directory.file("root/Applications/Tunewell.app/Contents/MacOS/tunewell-cli", bytes: 1_000_000)
        let bin = try directory.directory("root/usr/local/bin")
        let sbin = try directory.directory("root/usr/local/sbin")
        func link(_ name: String, in folder: URL, to destination: String) throws {
            try FileManager.default.createSymbolicLink(
                atPath: folder.appending(path: name).path(percentEncoded: false),
                withDestinationPath: destination
            )
        }
        try link("tunewell-cli", in: bin, to: app.url.appending(path: "Contents/MacOS/tunewell-cli").path(percentEncoded: false))
        try link("spotd", in: sbin, to: "../../../Applications/Tunewell.app/Contents/MacOS/spotd")
        try link("node", in: bin, to: directory.url.appending(path: "root/opt/node/bin/node").path(percentEncoded: false))
        try directory.file("root/usr/local/bin/tunewell")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.url.lastPathComponent, $0) })

        #expect(Set(found.keys) == ["tunewell-cli", "spotd"])
        for name in ["tunewell-cli", "spotd"] {
            #expect(found[name]?.kind == .commandLineTools)
            #expect(found[name]?.match.reason == .linksToTheApp)
            #expect(found[name]?.match.confidence == .certain)
        }
        // The size is the link's, never that of the tool it leads to.
        #expect(try #require(found["tunewell-cli"]?.size) < 64_000)
    }

    /// An installer can link the shell completions of an app's tools into the folders a Homebrew cask uses, in either
    /// prefix. A link there that leads into the app is the app's; a formula's link and a file are not.
    @Test func findsTheAppsShellCompletionLinks() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: directory.url.appending(path: "root/Applications/Tunewell.app", directoryHint: .isDirectory),
            bundleIdentifier: "net.example.client", name: "Tunewell"
        )
        let resources = try directory.directory("root/Applications/Tunewell.app/Contents/Resources")
        let folders = ["share/zsh/site-functions", "share/fish/vendor_completions.d", "etc/bash_completion.d", "share/pwsh/completions"]
        let places = folders.flatMap { ["usr/local/\($0)", "opt/homebrew/\($0)"] }
        for (index, place) in places.enumerated() {
            try FileManager.default.createSymbolicLink(
                atPath: try directory.directory("root/\(place)").appending(path: "tunewell\(index)").path(percentEncoded: false),
                withDestinationPath: resources.appending(path: "completion\(index)").path(percentEncoded: false)
            )
        }
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "root/opt/homebrew/share/zsh/site-functions/_git").path(percentEncoded: false),
            withDestinationPath: "../../../Cellar/git/2.51.0/share/zsh/site-functions/_git"
        )
        try directory.file("root/opt/homebrew/share/zsh/site-functions/_tunewell")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])
        let found = scan.leftovers.filter { $0.kind == .shellCompletions }

        #expect(Set(found.map(\.url.lastPathComponent)) == Set(places.indices.map { "tunewell\($0)" }))
        #expect(found.allSatisfy { $0.match.reason == .linksToTheApp && $0.match.confidence == .certain })
        #expect(!scan.leftovers.contains { ["_git", "_tunewell"].contains($0.url.lastPathComponent) })
    }

    /// Homebrew links a cask's commands into its own `bin`, `/opt/homebrew/bin` on Apple silicon (Cask Cookbook,
    /// `binary`). A link there that leads into the app is the app's, as one in `/usr/local/bin` is.
    @Test func findsTheAppsLinkInHomebrewsBin() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: directory.url.appending(path: "root/Applications/Tunewell.app", directoryHint: .isDirectory),
            bundleIdentifier: "net.example.client", name: "Tunewell"
        )
        try directory.file("root/Applications/Tunewell.app/Contents/MacOS/tunewell-cli")
        let bin = try directory.directory("root/opt/homebrew/bin")
        try FileManager.default.createSymbolicLink(
            atPath: bin.appending(path: "tunewell").path(percentEncoded: false),
            withDestinationPath: app.url.appending(path: "Contents/MacOS/tunewell-cli").path(percentEncoded: false)
        )
        try FileManager.default.createSymbolicLink(
            atPath: bin.appending(path: "wget").path(percentEncoded: false),
            withDestinationPath: "../Cellar/wget/1.25.0/bin/wget"
        )

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])

        let links = scan.leftovers.filter { $0.kind == .commandLineTools }
        #expect(links.map(\.url.lastPathComponent) == ["tunewell"])
        #expect(links.first?.match.reason == .linksToTheApp)
        #expect(links.first?.match.confidence == .certain)
    }

    /// The top of a Library holds macOS's own folders beside vendors' folders. There is a real app called
    /// Developer, and `~/Library/Developer` belongs to Xcode, so a match on the name alone is shown but never
    /// selected. An identifier still names the app wherever it sits. A folder scanned as a location of its own,
    /// such as `Preferences`, is never offered whole.
    @Test func showsAVendorsLibraryFolderWithoutEverSelectingIt() async throws {
        let directory = try TemporaryDirectory()
        let developer = InstalledApp(
            url: URL(filePath: "/Applications/Developer.app"),
            bundleIdentifier: "developer.example.app-Release",
            name: "Developer"
        )
        try directory.file("home/Library/Developer/Xcode/Archives/one.xcarchive/Info.plist", bytes: 64)
        try directory.file("home/Library/developer.example.app-Release/state.db", bytes: 64)
        try directory.file("home/Library/Preferences/unrelated.plist", bytes: 64)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            developer,
            installedApps: [developer]
        )
        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })

        #expect(found["home/Library/Developer"]?.match.heldBack == .namedLikeTheApp)
        #expect(found["home/Library/Developer"]?.match.isRecommended == false)
        #expect(found["home/Library/developer.example.app-Release"]?.match.isRecommended == true)
        #expect(found["home/Library/Preferences"] == nil, "a folder scanned as a location of its own was offered whole")
    }

    /// A vendor keeps each product's folder inside one of its own at the top of a Library. The product's folder is
    /// found there, a name alone shown but never selected, and the vendor's folder, which holds its other
    /// products, is never offered whole.
    @Test func findsAProductsFolderInsideItsVendorsFolderAtTheTopOfALibrary() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Hexachord.app"),
            bundleIdentifier: "org.example.hexachord",
            name: "Hexachord"
        )
        try directory.file("home/Library/Example Audio/Hexachord/presets.db", bytes: 64)
        try directory.file("home/Library/Example Audio/org.example.hexachord/state.db", bytes: 64)
        try directory.file("home/Library/Example Audio/Other Product/presets.db", bytes: 64)
        try directory.file("root/Library/Example Audio/Hexachord/samples.db", bytes: 64)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])
        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })

        #expect(Set(found.keys) == [
            "home/Library/Example Audio/Hexachord", "home/Library/Example Audio/org.example.hexachord",
            "root/Library/Example Audio/Hexachord",
        ])
        #expect(found["home/Library/Example Audio/Hexachord"]?.match.heldBack == .namedLikeTheApp)
        #expect(found["root/Library/Example Audio/Hexachord"]?.match.heldBack == .namedLikeTheApp)
        #expect(found["home/Library/Example Audio/org.example.hexachord"]?.match.isRecommended == true)
    }

    @Test func findsTheFoldersOfEachReleaseInsideItsMakersFolder() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Example Studio.app"),
            bundleIdentifier: "org.example.studio",
            name: "Example Studio"
        )
        let releases = [
            "Application Support/Example Maker/ExampleStudio2025.1", "Caches/Example Maker/ExampleStudio2025.2",
            "Logs/Example Maker/ExampleStudio2025.2",
        ]
        for release in releases {
            try directory.file("home/Library/\(release)/state.db", bytes: 64)
        }
        try directory.file("home/Library/Application Support/Example Maker/OtherProduct2025.1/state.db", bytes: 64)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])

        let home = directory.url.appending(path: "home/Library").path(percentEncoded: false) + "/"
        let found = scan.leftovers.map { String($0.url.path(percentEncoded: false).dropFirst(home.count)) }
        #expect(Set(found) == Set(releases))
    }

    /// A kernel extension an app's driver installed stays in `/Library/Extensions` after the app goes. It is found by
    /// the identifier it declares and listed, but only an administrator can move it and Peel's helper does not serve
    /// that folder, so it can never be selected.
    @Test(.permissionsHold) func listsTheAppsKernelExtensionWithoutEverSelectingIt() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Hexachord.app"),
            bundleIdentifier: "org.example.hexachord",
            name: "Hexachord"
        )
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "org.example.hexachord.driver"], format: .xml, options: 0
        )
        try info.write(to: directory.file("root/Library/Extensions/HexachordAudio.kext/Contents/Info.plist"))
        try directory.setPermissions(0o555, of: "root/Library/Extensions")
        defer { try? directory.setPermissions(0o755, of: "root/Library/Extensions") }

        let found = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])
        let scan = found.holdingBack(beyond: HelperReach(environment: environment(in: directory)), leaving: app.url)

        let kext = try #require(scan.leftovers.first { $0.url.lastPathComponent == "HexachordAudio.kext" })
        #expect(kext.requiresPrivileges)
        #expect(kext.match.heldBack == .beyondTheHelper)
        #expect(scan.leftovers.count == 1, "the kext was reached twice or its folder was offered")
    }

    /// A startup item an app's package installed in `/Library/StartupItems` is found by its folder's name and moved
    /// through the helper, which serves that folder; the folder itself is never offered.
    @Test(.permissionsHold) func findsTheAppsStartupItem() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Hexachord.app"),
            bundleIdentifier: "org.example.hexachord",
            name: "Hexachord"
        )
        try directory.file("root/Library/StartupItems/Hexachord/Hexachord", bytes: 64)
        try directory.file("root/Library/StartupItems/Hexachord/StartupParameters.plist", bytes: 64)
        try directory.setPermissions(0o555, of: "root/Library/StartupItems")
        defer { try? directory.setPermissions(0o755, of: "root/Library/StartupItems") }

        let found = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])
        let scan = found.holdingBack(beyond: HelperReach(environment: environment(in: directory)), leaving: app.url)

        let item = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Hexachord" })
        #expect(item.kind == .startupItems)
        #expect(item.requiresPrivileges)
        #expect(item.match.heldBack != .beyondTheHelper)
        #expect(scan.leftovers.count == 1)
    }

    /// A file system an app's package installed stays in `/Library/Filesystems` after the app goes, and is listed the
    /// same way: found by the identifier it declares, never selected, since the helper does not serve that folder.
    @Test(.permissionsHold) func listsTheAppsFileSystemWithoutEverSelectingIt() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Hexachord.app"),
            bundleIdentifier: "org.example.hexachord",
            name: "Hexachord"
        )
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "org.example.hexachord.filesystem"], format: .xml, options: 0
        )
        try info.write(to: directory.file("root/Library/Filesystems/hexfs.fs/Contents/Info.plist"))
        try directory.setPermissions(0o555, of: "root/Library/Filesystems")
        defer { try? directory.setPermissions(0o755, of: "root/Library/Filesystems") }

        let found = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])
        let scan = found.holdingBack(beyond: HelperReach(environment: environment(in: directory)), leaving: app.url)

        let fileSystem = try #require(scan.leftovers.first { $0.url.lastPathComponent == "hexfs.fs" })
        #expect(fileSystem.match.heldBack == .beyondTheHelper)
        #expect(scan.leftovers.count == 1, "the file system was reached twice or its folder was offered")
    }

    /// Apple: "The system automatically uninstalls any system extensions when the user deletes the corresponding
    /// app." The copy macOS activated in `/Library/SystemExtensions` is its own to remove, so it is never listed.
    @Test func neverListsASystemExtensionMacOSRemovesWithItsApp() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Hexachord.app"),
            bundleIdentifier: "org.example.hexachord",
            name: "Hexachord"
        )
        try directory.file(
            "root/Library/SystemExtensions/5DF88A99/org.example.hexachord.network.systemextension/Contents/Info.plist",
            bytes: 64
        )

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])

        #expect(scan.leftovers.isEmpty, "\(scan.leftovers.map(\.url.lastPathComponent))")
    }

    /// A folder Apple named for itself, such as `~/Library/Caches/com.apple.python`, belongs to someone else,
    /// so an app's name found inside it is only a guess.
    @Test func doesNotTakeANameFoundInsideApplesOwnFolder() async throws {
        let directory = try TemporaryDirectory()
        let developer = InstalledApp(
            url: URL(filePath: "/Applications/Developer.app"),
            bundleIdentifier: "developer.example.app-Release",
            name: "Developer"
        )
        try directory.file("home/Library/Caches/com.apple.python/Developer/wheel.whl", bytes: 64)
        try directory.file("home/Library/Caches/CrashReporter/Developer/report.txt", bytes: 64)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            developer,
            installedApps: [developer]
        )
        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })

        #expect(found["home/Library/Caches/com.apple.python/Developer"]?.match.heldBack == .insideAnotherAppsFolder)
        // A folder no app claims is somebody's too, and its name says nothing of this app or its maker.
        #expect(found["home/Library/Caches/CrashReporter/Developer"]?.match.heldBack == .namedLikeTheApp)
    }

    /// Vendors keep a folder of their own in `/Users/Shared`. What is in there belongs to every account on the
    /// Mac, so it is shown but never selected, even when it is certainly the app's.
    @Test func looksInsideAVendorsFolderInTheSharedFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Users/Shared/Acme/net.example.client/licence.dat", bytes: 64)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )
        let found = try #require(scan.leftovers.first)

        #expect(found.url.lastPathComponent == "net.example.client")
        #expect(found.match.heldBack == .sharedWithEveryone)
        #expect(found.match.isRecommended == false)
    }

    /// A container is almost always named by its app's identifier, and then nothing is read. When it is named by
    /// a UUID instead, the identifier in its metadata file names it.
    @Test func readsAContainersOwnIdentifierWhenItIsNamedByAUUID() async throws {
        let directory = try TemporaryDirectory()
        let metadata = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>MCMMetadataIdentifier</key><string>%@</string></dict></plist>
        """
        try directory.file(
            "home/Library/Containers/3F2504E0-4F89-11D3-9A0C-0305E82C3301/.com.apple.containermanagerd.metadata.plist",
            contents: Data(metadata.replacingOccurrences(of: "%@", with: "net.example.client").utf8)
        )
        try directory.file(
            "home/Library/Containers/9B1DEB4D-3B7D-4BAD-9BDD-2B0D7B3DCB6D/.com.apple.containermanagerd.metadata.plist",
            contents: Data(metadata.replacingOccurrences(of: "%@", with: "com.example.other").utf8)
        )

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(
            tunewell,
            installedApps: [tunewell]
        )

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["3F2504E0-4F89-11D3-9A0C-0305E82C3301"])
        #expect(scan.leftovers.first?.match.reason == .bundleIdentifier)
        #expect(scan.leftovers.first?.match.confidence == .certain)
    }

    @Test func findsABrowsersManifestThatRunsAProgramInsideTheApp() async throws {
        let directory = try TemporaryDirectory()
        let hosts = "home/Library/Application Support/Google/Chrome/NativeMessagingHosts"
        try directory.file("\(hosts)/com.example.bridge.json", contents: Data("""
        {"name": "com.example.bridge", "path": "/Applications/Tunewell.app/Contents/MacOS/bridge", "type": "stdio"}
        """.utf8))
        try directory.file("\(hosts)/org.example.other.json", contents: Data("""
        {"name": "org.example.other", "path": "/Applications/Other.app/Contents/MacOS/bridge", "type": "stdio"}
        """.utf8))
        let scanner = LeftoverScanner(environment: environment(in: directory))

        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        let manifests = scan.leftovers.filter { $0.url.pathExtension == "json" }
        #expect(manifests.map(\.url.lastPathComponent) == ["com.example.bridge.json"])
        #expect(manifests.first?.match.confidence == .certain)
        #expect(manifests.first?.match.isRecommended == true)
    }

    @Test func aFolderWithAPasswordDatabaseOrItsKeyFileIsNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Tunewell/Backups/Passwords.kdbx")
        try directory.file("home/Library/Application Support/net.example.client/Vault.keyx")

        let scanner = LeftoverScanner(environment: environment(in: directory))

        let scan = await scanner.scan(tunewell, installedApps: [tunewell])
        let held = scan.leftovers.filter { ["Tunewell", "net.example.client"].contains($0.url.lastPathComponent) }
        #expect(held.count == 2)
        #expect(held.allSatisfy { $0.match.heldBack == .holdsAPasswordDatabase && !$0.match.isRecommended })
    }

    @Test func dataKeptOnlyOnThisMacIsShownAndNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Signal/sql/db.sqlite", bytes: 4_096)
        let signal = InstalledApp(
            url: URL(filePath: "/Applications/Signal.app"), bundleIdentifier: "org.example.signal", name: "Signal"
        )

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(signal, installedApps: [signal])

        let history = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Signal" })
        #expect(history.match.heldBack == .holdsMessageHistory)
        #expect(!history.match.isRecommended)
    }

    @Test func findsTheAppsCrashReportsByTheBundleTheyNameAndNeverSelectsThem() async throws {
        let directory = try TemporaryDirectory()
        let reports = "home/Library/Logs/DiagnosticReports"
        let ours = report(bundleIdentifier: "net.example.client")
        try directory.file("\(reports)/Tunewell-2026-09-01-101010.ips", contents: ours)
        try directory.file("\(reports)/Retired/Tunewell-2026-08-01-090000.ips", contents: ours)
        let another = report(bundleIdentifier: "org.example.tunewell")
        try directory.file("\(reports)/Tunewell-2026-09-02-111111.ips", contents: another)

        let scanner = LeftoverScanner(environment: environment(in: directory))
        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        #expect(scan.leftovers.map(\.url.lastPathComponent).sorted() == [
            "Tunewell-2026-08-01-090000.ips", "Tunewell-2026-09-01-101010.ips",
        ])
        #expect(scan.leftovers.allSatisfy { $0.match.reason == .bundleIdentifier && $0.match.confidence == .certain })
        #expect(scan.leftovers.allSatisfy { $0.match.heldBack == .crashReport })
    }

    /// A `.diag` names the process it watched, not a bundle, so it is never the app's however its name reads, even
    /// when the process is one of the app's helpers named by an identifier that begins with the app's.
    @Test func neverTakesADiagnosticReportForTheApp() async throws {
        let directory = try TemporaryDirectory()
        let reports = "home/Library/Logs/DiagnosticReports"
        try directory.file("\(reports)/net.example.client.agent_2026-09-29-214451_MacBook-Air.diag", bytes: 12_000)
        try directory.file("\(reports)/Retired/net.example.client.agent_2026-09-30-101010_Mac.diag", bytes: 12_000)
        let scanner = LeftoverScanner(environment: environment(in: directory))

        let scan = await scanner.scan(tunewell, installedApps: [tunewell])

        #expect(scan.leftovers.isEmpty)
    }

    private func report(bundleIdentifier: String) -> Data {
        Data("""
        {"app_name":"Tunewell","bug_type":"309","bundleID":"\(bundleIdentifier)","name":"Tunewell","incident_id":"1"}
        {"procName":"Tunewell","exception":{"type":"EXC_CRASH"}}
        """.utf8)
    }

    private func job(program: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>Label</key><string>a.job</string>
        <key>Program</key><string>\(program)</string>
        </dict></plist>
        """.utf8)
    }

    private func plist(_ bundleIdentifier: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>\(bundleIdentifier)</string></dict></plist>
        """.utf8)
    }
}
