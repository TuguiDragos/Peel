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
                match: LeftoverMatch(reason: .bundleIdentifier, confidence: .likely, sharedWith: []), size: 10, isMeasured: true, requiresPrivileges: false
            )
            return (location, [leftover])
        }

        #expect(LeftoverScanner.merged([found(in: support), found(in: recent)]).map(\.kind) == [.recentDocuments])
        #expect(LeftoverScanner.merged([found(in: recent), found(in: support)]).map(\.kind) == [.recentDocuments])
    }

    /// Folders that no app claims are looked into one at a time, so the scan has to notice a stop between them.
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...30 {
            try directory.directory("home/Library/Application Support/Vendor \(index)/com.spotify.client")
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory),
            userCacheDirectory: directory.url.appending(path: "var/C", directoryHint: .isDirectory),
            userTemporaryDirectory: directory.url.appending(path: "var/T", directoryHint: .isDirectory)
        )
        let unanswered = Unanswered()
        let scanner = LeftoverScanner(environment: environment, measure: unanswered.walk)
        let spotify = spotify

        let stop = try await unanswered.stop {
            _ = await scanner.scan(spotify, installedApps: [spotify])
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }

    private let spotify = InstalledApp(
        url: URL(filePath: "/Applications/Spotify.app"),
        bundleIdentifier: "com.spotify.client",
        name: "Spotify"
    )

    private func environment(in directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory),
            userCacheDirectory: directory.url.appending(path: "var/C", directoryHint: .isDirectory),
            userTemporaryDirectory: directory.url.appending(path: "var/T", directoryHint: .isDirectory)
        )
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
        try directory.directory("home/Library/Caches/com.spotify.client")
        let asked = Mutex<[String]>([])
        let scanner = LeftoverScanner(
            environment: environment(in: directory),
            measure: { _ in FolderContents(size: 1, holdsRepository: false) },
            refuses: { path, home in
                asked.withLock { $0.append(URL(filePath: path).lastPathComponent) }
                return ProtectedData.refuses(path, home: home)
            }
        )
        let spotify = spotify

        let scan = await scanner.scan(spotify, installedApps: [spotify])

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["com.spotify.client"])
        #expect(asked.withLock { $0.sorted() } == ["com.example.other", "com.spotify.client"])
    }

    @Test func findsMatchingItemsAcrossLocations() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Preferences/com.spotify.client.plist")
        try directory.file("home/Library/Caches/com.spotify.client/Data/cache.db", bytes: 64_000)
        try directory.directory("home/Library/Application Support/Spotify")
        try directory.file("home/Library/Caches/com.example.other/cache.db")
        try directory.file("root/Library/LaunchAgents/com.spotify.webhelper.plist")
        try directory.directory("var/C/com.spotify.client")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })
        #expect(Set(found.keys) == [
            "home/Library/Preferences/com.spotify.client.plist",
            "home/Library/Caches/com.spotify.client",
            "home/Library/Application Support/Spotify",
            "root/Library/LaunchAgents/com.spotify.webhelper.plist",
            "var/C/com.spotify.client",
        ])
        #expect(scan.leftovers.first?.url.lastPathComponent == "com.spotify.client")
        #expect(scan.leftovers.first?.kind == .caches)
        let launchAgent = try #require(found["root/Library/LaunchAgents/com.spotify.webhelper.plist"])
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

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(namesake, installedApps: [namesake])

        let folder = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Music" })
        #expect(folder.match.sharedWith == ["com.apple.Music"])
        #expect(!folder.match.isRecommended)
    }

    /// A folder that could not be measured in time is not an empty one. It may be a large folder with a
    /// repository inside, which is exactly the case the repository rule is for.
    @Test func aFolderThatCouldNotBeMeasuredIsShownAndNotSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Spotify/checkout/.git/HEAD")
        try directory.file("home/Library/Caches/com.spotify.client/cache.db", bytes: 4_096)
        let slow = directory.url.appending(path: "home/Library/Application Support/Spotify")

        let scanner = LeftoverScanner(environment: environment(in: directory)) { url in
            url.lastPathComponent == slow.lastPathComponent ? nil : await FileSize.contents(of: url)
        }
        let scan = await scanner.scan(spotify, installedApps: [spotify])

        let unmeasured = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Spotify" })
        // Listed first, as every list does with a size it does not know: it is most likely the biggest.
        #expect(scan.leftovers.first?.url.lastPathComponent == "Spotify", "the folder that ran out of time was listed last")
        #expect(scan.adding([]).leftovers.first?.url.lastPathComponent == "Spotify")
        #expect(unmeasured.match.heldBack == .notMeasured)
        #expect(!unmeasured.match.isRecommended)
        #expect(!unmeasured.isMeasured)
        let measured = try #require(scan.leftovers.first { $0.url.lastPathComponent == "com.spotify.client" })
        #expect(measured.match.heldBack == nil)
        #expect(measured.match.isRecommended)
        #expect(measured.isMeasured)
    }

    /// The recent documents folder is a location of its own and also sits two levels inside Application Support,
    /// which is searched two levels deep. A file reached both ways is listed once: listed twice, it would be
    /// counted twice, and its second move would be reported as a failure.
    @Test func aFileReachedTwoWaysIsListedOnce() async throws {
        let directory = try TemporaryDirectory()
        let list = "home/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.spotify.client.sfl3"
        try directory.file(list)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        let found = scan.leftovers.filter { $0.url.lastPathComponent == "com.spotify.client.sfl3" }
        #expect(found.count == 1, "listed \(found.count) times")
        #expect(found.first?.kind == .recentDocuments)
        #expect(found.first?.match.confidence == .certain, "the stronger of the two claims is the one kept")
    }

    /// A cask may write a folder's path with a trailing slash, while the scanner writes it without one. It is
    /// the same folder, and `adding(_:)` compares paths rather than URLs, so it stays one row.
    @Test func aPathACaskSpellsWithASlashIsNotASecondRow() {
        let match = LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: [])
        let found = Leftover(url: URL(filePath: "/Users/x/Library/Caches/com.spotify.client"), kind: .caches, match: match, size: 10, isMeasured: true, requiresPrivileges: false)
        let named = Leftover(
            url: URL(filePath: "/Users/x/Library/Caches/com.spotify.client/", directoryHint: .isDirectory),
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
        try directory.file("home/Library/Application Support/SomeVendor/Spotify/notes.db")
        try directory.file("home/Library/Application Support/SomeVendor/com.spotify.client/state.db")
        try directory.file("home/Library/Application Support/Nobody/Spotify/notes.db")
        let other = InstalledApp(url: URL(filePath: "/Applications/SomeVendor.app"), bundleIdentifier: "com.somevendor.app", name: "SomeVendor")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify, other])
        let byPath = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.url.path(percentEncoded: false).components(separatedBy: "Application Support/").last ?? "", $0) })

        #expect(byPath["SomeVendor/Spotify"]?.match.heldBack == .insideAnotherAppsFolder)
        #expect(byPath["SomeVendor/Spotify"]?.match.isRecommended == false)
        #expect(byPath["SomeVendor/com.spotify.client"]?.match.isRecommended == true, "an identifier names the app wherever it sits")
        #expect(byPath["Nobody/Spotify"]?.match.isRecommended == true, "a folder no installed app answers to is nobody's")
    }

    /// Leaving a page cancels its scan, and a canceled scan stops measuring. Otherwise, moving through a list of
    /// apps would leave a scan running for every app passed.
    @Test func aScanThatWasCanceledStopsMeasuring() async throws {
        let directory = try TemporaryDirectory()
        for index in 0..<40 {
            try directory.file("home/Library/Caches/com.spotify.client.part\(index)/cache.db")
        }
        let measured = Mutex(0)
        let scanner = LeftoverScanner(environment: environment(in: directory)) { _ in
            measured.withLock { $0 += 1 }
            // Holds the first measurement until the scan has been canceled.
            while !Task.isCancelled { await Task.yield() }
            return FolderContents(size: 1, holdsRepository: false)
        }

        let scan = Task { await scanner.scan(spotify, installedApps: [spotify]) }
        while measured.withLock({ $0 }) == 0 { await Task.yield() }
        scan.cancel()
        _ = await scan.value

        #expect(measured.withLock { $0 } == 1, "it went on measuring after it was canceled")
    }

    /// An app can keep a whole photo, music, or video library beside its settings. `RemovalGuard` refuses to
    /// move a folder holding one, so the row says so from the start instead of failing at the move.
    @Test func aFolderThatHoldsALibraryIsShownAndLeftAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Spotify/Libraries/Main.musiclibrary/Library.musicdb")
        try directory.file("home/Library/Caches/com.spotify.client/cache.db")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        let support = try #require(scan.leftovers.first { $0.kind == .applicationSupport })
        #expect(support.match.heldBack == .holdsALibrary)
        #expect(!support.match.isRecommended)
        #expect(scan.leftovers.first { $0.kind == .caches }?.match.isRecommended == true)
    }

    /// A sandboxed app keeps what its user made in `Data/Documents`, inside the container an uninstall lists.
    @Test func aContainerThatHoldsDocumentsIsShownAndLeftAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Containers/com.spotify.client/Data/Documents/playlist.txt")
        try directory.file("home/Library/Group Containers/ABCDE12345.com.spotify.client/cache.db")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        let container = try #require(scan.leftovers.first { $0.kind == .containers })
        #expect(container.match.heldBack == .holdsDocuments)
        #expect(!container.match.isRecommended)

        try FileManager.default.removeItem(at: container.url.appending(path: "Data/Documents/playlist.txt"))
        let emptied = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])
        #expect(try #require(emptied.leftovers.first { $0.kind == .containers }).match.isRecommended)
    }

    @Test func reportsUnreadableLocations() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Logs/Spotify/log.txt")
        try directory.setPermissions(0o000, of: "home/Library/Logs")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Logs") }

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        #expect(scan.leftovers.isEmpty)
        #expect(scan.unreadableLocations.map(\.kind) == [.logs])
    }

    @Test func flagsItemsInReadOnlyLocationsAsRequiringPrivileges() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Library/LaunchDaemons/com.spotify.client.helper.plist")
        try directory.file("home/Library/Preferences/com.spotify.client.plist")
        try directory.setPermissions(0o555, of: "root/Library/LaunchDaemons")
        defer { try? directory.setPermissions(0o755, of: "root/Library/LaunchDaemons") }

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        let privileges = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.kind, $0.requiresPrivileges) })
        #expect(privileges == [.launchDaemons: true, .preferences: false])
    }

    /// Two real cases: a crash reporter keeps a folder for each app, and macOS keeps a help cache for each
    /// app. The inner folder carries the app's identifier, but the folder around it belongs to someone else.
    @Test func findsFilesBuriedInSomebodyElsesFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.plausiblelabs.crashreporter.data/com.spotify.client/report.plist")
        try directory.file("home/Library/Caches/com.apple.helpd/Generated/com.spotify.client.help-1.0/index.html")
        try directory.file("home/Library/Application Support/SomeVendor/Spotify/state.json")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })
        #expect(Set(found.keys) == [
            "home/Library/Caches/com.plausiblelabs.crashreporter.data/com.spotify.client",
            "home/Library/Caches/com.apple.helpd/Generated/com.spotify.client.help-1.0",
            "home/Library/Application Support/SomeVendor/Spotify",
        ])
        #expect(found["home/Library/Caches/com.plausiblelabs.crashreporter.data/com.spotify.client"]?.match.reason == .bundleIdentifier)
        #expect(found["home/Library/Caches/com.apple.helpd/Generated/com.spotify.client.help-1.0"]?.match.reason == .bundleIdentifierPrefix)
    }

    /// The scan looks inside a limited number of other folders. At the limit it reports the location, and the
    /// folders it looked into are chosen in name order, not in the order the disk listed them.
    @Test func saysWhenItStoppedLookingInsideFolders() async throws {
        let directory = try TemporaryDirectory()
        for index in 0..<6 {
            try directory.directory("home/Library/Application Support/Aardvark \(index)")
        }
        try directory.file("home/Library/Application Support/SomeVendor/Spotify/state.json")
        let scanner = LeftoverScanner(environment: environment(in: directory), measure: LeftoverScanner.walk, nestedFolderLimit: 5)

        let scan = await scanner.scan(spotify, installedApps: [spotify])

        #expect(scan.leftovers.isEmpty, "the folder past the limit was looked into")
        #expect(scan.cutShortLocations.map(\.kind) == [.applicationSupport])

        let whole = await LeftoverScanner(environment: environment(in: directory), measure: LeftoverScanner.walk).scan(spotify, installedApps: [spotify])
        #expect(whole.leftovers.map(\.url.lastPathComponent) == ["Spotify"])
        #expect(whole.cutShortLocations.isEmpty)
    }

    /// Inside a folder that is not the app's, only a match strong enough to name the app on its own is taken. A
    /// shared vendor prefix, or a name the file only starts with, is not enough there.
    @Test func leavesGuessesInsideSomebodyElsesFolderAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/SomeVendor/com.spotify.notthisapp.plist")
        try directory.file("home/Library/Caches/SomeVendor/Spotify Installer Log.txt")
        try directory.file("home/Library/Caches/SomeVendor/Spotify")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["Spotify"])
    }

    /// A folder that is already the app's own is reported whole; its contents are not listed again.
    @Test func doesNotLookInsideAFolderItAlreadyFound() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Caches/com.spotify.client/com.spotify.client.db")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["com.spotify.client"])
    }

    /// A container belongs entirely to the app it is named for, so the scan never looks inside another app's.
    @Test func staysOutOfOtherAppsContainers() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Containers/com.example.other/Data/com.spotify.client.plist")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        #expect(scan.leftovers.isEmpty)
    }

    /// Apps installed for every account on the Mac can keep their files in `/Users/Shared`.
    @Test func findsWhatAnAppLeftInTheSharedFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Users/Shared/Spotify/library.db", bytes: 4_000)
        try directory.file("root/Users/Shared/Something Else/notes.txt")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["Spotify"])
        #expect(scan.leftovers.first?.kind == .sharedFolder)
        #expect(scan.leftovers.first?.match.reason == .name)
    }

    /// Some apps keep hidden settings at the top of the home folder, and tools that follow the XDG convention
    /// use `.config`. A few apps keep a plain folder there, which is shown but never selected. Nothing inside
    /// `Documents` is looked at.
    @Test func findsWhatAnAppHidesInTheHomeFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/.spotify/state.json")
        try directory.file("home/.config/spotify/config.toml")
        try directory.file("home/.ssh/id_ed25519")
        try directory.file("home/Spotify/my own notes.txt")
        try directory.file("home/Documents/Spotify")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(
            scan.leftovers.map { (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(Set(found.keys) == ["home/.spotify", "home/.config/spotify", "home/Spotify"])
        #expect(found["home/.spotify"]?.kind == .hiddenHomeFiles)
        #expect(found["home/Spotify"]?.kind == .homeFolder)
        #expect(found["home/Spotify"]?.match.isRecommended == false)
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
        try directory.file("home/Library/Application Support/Spotify/settings.json")
        try directory.file("home/Library/Application Support/Spotify/workspaces/a/b/project/.git/HEAD")
        try directory.file("home/Library/Caches/com.spotify.client/cache.db", bytes: 64_000)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })
        let support = try #require(found["home/Library/Application Support/Spotify"], "the folder disappeared instead of being shown")
        #expect(support.match.reason == .name)
        #expect(!support.match.isRecommended, "a folder holding a checkout was selected")
        #expect(support.match.heldBack == .holdsRepository, "the row could not say why it was left alone")
        // A folder beside it, with no repository in it, is untouched by the rule.
        #expect(found["home/Library/Caches/com.spotify.client"]?.match.isRecommended == true)
        #expect(found["home/Library/Caches/com.spotify.client"]?.match.heldBack == nil)
    }

    /// A folder macOS will not open would read as empty, and an empty folder of the app's own would be selected.
    /// From macOS 27, access to another team's container is denied outright rather than prompted for.
    @Test func aLeftoverThatCannotBeReadIsNeverSelectedAndHasNoSize() async throws {
        let directory = try TemporaryDirectory()
        let container = try directory.directory("home/Library/Containers/com.spotify.client")
        try directory.file("home/Library/Containers/com.spotify.client/Data/Library/Caches/blob", bytes: 64_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: container.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: container.path(percentEncoded: false)) }

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])
        let found = try #require(scan.leftovers.first { $0.url.lastPathComponent == "com.spotify.client" })

        #expect(found.match.heldBack == .couldNotBeRead, "a folder nothing could be read from was taken for an empty one")
        #expect(!found.match.isRecommended)
        #expect(!found.isMeasured)
    }

    /// An exclusion inside replaces `notMeasured` as the reason, but the folder's size stays unknown, not zero.
    @Test func aFolderHoldingAnExclusionKeepsASizeNobodyKnows() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/Spotify/kept/notes.txt")
        let folder = directory.url.appending(path: "home/Library/Application Support/Spotify")
        let exclusions = Exclusions(paths: [folder.appending(path: "kept")])

        let scanner = LeftoverScanner(environment: environment(in: directory), exclusions: exclusions) { url in
            url.lastPathComponent == folder.lastPathComponent ? nil : await FileSize.contents(of: url)
        }
        let scan = await scanner.scan(spotify, installedApps: [spotify])

        let found = try #require(scan.leftovers.first { $0.url.lastPathComponent == "Spotify" })
        #expect(found.match.heldBack == .holdsAnExclusion)
        #expect(!found.isMeasured, "a folder nobody measured was given a size of zero")
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
        let unread: LeftoverScanner.Measure = { _ in FolderContents(size: 0, holdsRepository: false, couldNotBeRead: true) }
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

    /// Plug-ins are found in the user's Library and the system's, including inside a vendor's own folder.
    @Test func findsThePlugInsAnAppInstalled() async throws {
        let directory = try TemporaryDirectory()
        let massive = InstalledApp(
            url: URL(filePath: "/Applications/Massive.app"),
            bundleIdentifier: "com.native-instruments.massive",
            name: "Massive"
        )
        try directory.file("home/Library/Audio/Plug-Ins/VST3/Massive.vst3/Contents/Info.plist", bytes: 512)
        try directory.file("root/Library/Audio/Plug-Ins/Components/Massive.component/Contents/Info.plist", bytes: 512)
        try directory.file("root/Library/Audio/Plug-Ins/VST/Native Instruments/Massive.vst/Contents/Info.plist", bytes: 512)
        try directory.file("root/Library/QuickLook/Somebody Else.qlgenerator/Contents/Info.plist", bytes: 512)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(massive, installedApps: [massive])

        let root = directory.url.path(percentEncoded: false)
        let found = Set(scan.leftovers.map { String($0.url.path(percentEncoded: false).dropFirst(root.count)) })
        #expect(found == [
            "home/Library/Audio/Plug-Ins/VST3/Massive.vst3",
            "root/Library/Audio/Plug-Ins/Components/Massive.component",
            "root/Library/Audio/Plug-Ins/VST/Native Instruments/Massive.vst",
        ])
        #expect(scan.leftovers.allSatisfy { $0.kind == .plugIns })
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

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(central, installedApps: [central])

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["Q10.vst3"])
        #expect(scan.leftovers.first?.match.reason == .vendorPrefix)
        #expect(scan.leftovers.first?.match.confidence == .possible)
        #expect(scan.leftovers.first?.match.isRecommended == false)
    }

    /// A launchd job is named by whoever wrote it, so a job whose program sits inside the app is the app's,
    /// whatever its file is called. That match is certain and outranks a weaker match on the file name.
    @Test func findsAJobByTheProgramItRuns() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/LaunchAgents/com.acmesoft.updater.plist", contents: job(program: "/Applications/Spotify.app/Contents/MacOS/Updater"))
        try directory.file("home/Library/LaunchAgents/com.spotify.nagger.plist", contents: job(program: "/Applications/Spotify.app/Contents/Helpers/Nagger"))
        try directory.file("home/Library/LaunchAgents/com.elsewhere.agent.plist", contents: job(program: "/Applications/Other.app/Contents/MacOS/Agent"))
        try directory.file("home/Library/LaunchAgents/com.relative.agent.plist", contents: job(program: "sleep"))

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.url.lastPathComponent, $0.match) })

        #expect(Set(found.keys) == ["com.acmesoft.updater.plist", "com.spotify.nagger.plist"])
        #expect(found["com.acmesoft.updater.plist"]?.reason == .launchdJob)
        #expect(found["com.acmesoft.updater.plist"]?.confidence == .certain)
        #expect(found["com.acmesoft.updater.plist"]?.isRecommended == true)
        // By its name alone it would be only a vendor prefix match; what it runs settles it.
        #expect(found["com.spotify.nagger.plist"]?.reason == .launchdJob)
    }

    /// A link in `/usr/local/bin` or `/usr/local/sbin` is named for the tool it runs, such as `docker` or `code`,
    /// which says nothing about whose it is. Where it leads does.
    @Test func findsALinkToAToolInsideTheApp() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(url: directory.url.appending(path: "root/Applications/Spotify.app", directoryHint: .isDirectory), bundleIdentifier: "com.spotify.client", name: "Spotify")
        try directory.file("root/Applications/Spotify.app/Contents/MacOS/spotify-cli", bytes: 1_000_000)
        let bin = try directory.directory("root/usr/local/bin")
        let sbin = try directory.directory("root/usr/local/sbin")
        func link(_ name: String, in folder: URL, to destination: String) throws {
            try FileManager.default.createSymbolicLink(atPath: folder.appending(path: name).path(percentEncoded: false), withDestinationPath: destination)
        }
        try link("spotify-cli", in: bin, to: app.url.appending(path: "Contents/MacOS/spotify-cli").path(percentEncoded: false))
        try link("spotd", in: sbin, to: "../../../Applications/Spotify.app/Contents/MacOS/spotd")
        try link("node", in: bin, to: directory.url.appending(path: "root/opt/node/bin/node").path(percentEncoded: false))
        try directory.file("root/usr/local/bin/spotify")

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(app, installedApps: [app])
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map { ($0.url.lastPathComponent, $0) })

        #expect(Set(found.keys) == ["spotify-cli", "spotd"])
        for name in ["spotify-cli", "spotd"] {
            #expect(found[name]?.kind == .commandLineTools)
            #expect(found[name]?.match.reason == .linksToTheApp)
            #expect(found[name]?.match.confidence == .certain)
        }
        // The size is the link's, never that of the tool it leads to.
        #expect(try #require(found["spotify-cli"]?.size) < 64_000)
    }

    /// The top of a Library holds macOS's own folders beside vendors' folders. There is a real app called
    /// Developer, and `~/Library/Developer` belongs to Xcode, so a match on the name alone is shown but never
    /// selected. An identifier still names the app wherever it sits. A folder scanned as a location of its own,
    /// such as `Preferences`, is never offered whole.
    @Test func showsAVendorsLibraryFolderWithoutEverSelectingIt() async throws {
        let directory = try TemporaryDirectory()
        let developer = InstalledApp(
            url: URL(filePath: "/Applications/Developer.app"),
            bundleIdentifier: "developer.apple.wwdc-Release",
            name: "Developer"
        )
        try directory.file("home/Library/Developer/Xcode/Archives/one.xcarchive/Info.plist", bytes: 64)
        try directory.file("home/Library/developer.apple.wwdc-Release/state.db", bytes: 64)
        try directory.file("home/Library/Preferences/unrelated.plist", bytes: 64)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(developer, installedApps: [developer])
        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })

        #expect(found["home/Library/Developer"]?.match.heldBack == .namedLikeTheApp)
        #expect(found["home/Library/Developer"]?.match.isRecommended == false)
        #expect(found["home/Library/developer.apple.wwdc-Release"]?.match.isRecommended == true)
        #expect(found["home/Library/Preferences"] == nil, "a folder scanned as a location of its own was offered whole")
    }

    /// A folder Apple named for itself, such as `~/Library/Caches/com.apple.python`, belongs to someone else,
    /// so an app's name found inside it is only a guess.
    @Test func doesNotTakeANameFoundInsideApplesOwnFolder() async throws {
        let directory = try TemporaryDirectory()
        let developer = InstalledApp(
            url: URL(filePath: "/Applications/Developer.app"),
            bundleIdentifier: "developer.apple.wwdc-Release",
            name: "Developer"
        )
        try directory.file("home/Library/Caches/com.apple.python/Developer/wheel.whl", bytes: 64)
        try directory.file("home/Library/Caches/CrashReporter/Developer/report.txt", bytes: 64)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(developer, installedApps: [developer])
        let root = directory.url.path(percentEncoded: false)
        let found = Dictionary(uniqueKeysWithValues: scan.leftovers.map {
            (String($0.url.path(percentEncoded: false).dropFirst(root.count)), $0)
        })

        #expect(found["home/Library/Caches/com.apple.python/Developer"]?.match.heldBack == .insideAnotherAppsFolder)
        // A plain vendor folder that no app claims is not affected.
        #expect(found["home/Library/Caches/CrashReporter/Developer"]?.match.isRecommended == true)
    }

    /// Vendors keep a folder of their own in `/Users/Shared`. What is in there belongs to every account on the
    /// Mac, so it is shown but never selected, even when it is certainly the app's.
    @Test func looksInsideAVendorsFolderInTheSharedFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Users/Shared/Acme/com.spotify.client/licence.dat", bytes: 64)

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])
        let found = try #require(scan.leftovers.first)

        #expect(found.url.lastPathComponent == "com.spotify.client")
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
            contents: Data(metadata.replacingOccurrences(of: "%@", with: "com.spotify.client").utf8)
        )
        try directory.file(
            "home/Library/Containers/9B1DEB4D-3B7D-4BAD-9BDD-2B0D7B3DCB6D/.com.apple.containermanagerd.metadata.plist",
            contents: Data(metadata.replacingOccurrences(of: "%@", with: "com.example.other").utf8)
        )

        let scan = await LeftoverScanner(environment: environment(in: directory)).scan(spotify, installedApps: [spotify])

        #expect(scan.leftovers.map(\.url.lastPathComponent) == ["3F2504E0-4F89-11D3-9A0C-0305E82C3301"])
        #expect(scan.leftovers.first?.match.reason == .bundleIdentifier)
        #expect(scan.leftovers.first?.match.confidence == .certain)
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
