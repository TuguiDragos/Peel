import Foundation
@testable import PeelCore
import Testing

struct ExclusionsTests {
    /// A slash and a combining mark after it are one `Character`, so a name that begins with the mark is not
    /// "inside" its folder to a comparison made on characters. Compared name by name, what sits in an excluded
    /// folder is excluded whatever its name begins with, and an excluded item inside a folder is still held.
    @Test func whatIsInsideAnExcludedFolderIsExcludedWhateverItsNameBeginsWith() {
        let folder = URL(filePath: "/Users/x/Projects", directoryHint: .isDirectory)
        let exclusions = Exclusions(paths: [folder])
        let marked = URL(filePath: "/Users/x/Projects/\u{301}notes.txt")

        #expect(exclusions.excludes(marked), "a file inside an excluded folder was not excluded")
        #expect(Exclusions(paths: [marked]).holds(folder), "a folder holding an excluded file could be moved")
        #expect(!exclusions.excludes(URL(filePath: "/Users/x/Projects Old/notes.txt")))
    }

    @Test func coversAnItemAndEverythingInsideIt() {
        let exclusions = Exclusions(paths: [URL(filePath: "/Users/x/Library/Application Support/Keep")])

        #expect(exclusions.excludes(URL(filePath: "/Users/x/Library/Application Support/Keep")))
        #expect(exclusions.excludes(URL(filePath: "/Users/x/Library/Application Support/Keep/data.db")))
        #expect(!exclusions.excludes(URL(filePath: "/Users/x/Library/Application Support/Keeper")))
        #expect(!exclusions.excludes(URL(filePath: "/Users/x/Library/Application Support")))
        #expect(!Exclusions.none.excludes(URL(filePath: "/Users/x/anything")))
    }

    /// A folder chosen in an open panel carries a trailing slash; one built from a path string does not.
    @Test func matchesAFolderHoweverItsURLWasMade() {
        let chosen = Exclusions(paths: [URL(filePath: "/Users/x/Library/Caches/uv", directoryHint: .isDirectory)])

        #expect(chosen.excludes(URL(filePath: "/Users/x/Library/Caches/uv")))
        #expect(chosen.excludes(URL(filePath: "/Users/x/Library/Caches/uv", directoryHint: .isDirectory)))
        #expect(chosen.excludes(URL(filePath: "/Users/x/Library/Caches/uv/archive")))
        #expect(!chosen.excludes(URL(filePath: "/Users/x/Library/Caches/uvx")))
    }

    /// `brew uninstall` deletes for good, so the Homebrew page never runs it on a package that would take
    /// something the user excluded.
    @Test func keepsWhatBrewUninstallWouldDeleteForGood() {
        let prefix = URL(filePath: "/opt/homebrew", directoryHint: .isDirectory)
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")
        let cask = HomebrewPackage(name: "example", kind: .cask, appTargets: ["/Applications/Example.app"], quitIdentifiers: ["com.example.app"])
        let formula = HomebrewPackage(name: "wget", kind: .formula)

        #expect(Exclusions(paths: [URL(filePath: "/Applications/Example.app")]).excludes(cask, apps: [], prefix: prefix))
        #expect(Exclusions(paths: [URL(filePath: "/Applications/Example.app/Contents/Resources/keep")]).excludes(cask, apps: [], prefix: prefix))
        #expect(Exclusions(bundleIdentifiers: ["com.example.app"]).excludes(cask, apps: [app], prefix: prefix))
        #expect(Exclusions(bundleIdentifiers: ["com.example.app"]).excludes(cask, apps: [], prefix: prefix), "the identifier it quits names it too")
        #expect(Exclusions(paths: [URL(filePath: "/opt/homebrew/Caskroom/example")]).excludes(cask, apps: [], prefix: prefix))
        #expect(Exclusions(paths: [URL(filePath: "/opt/homebrew")]).excludes(formula, apps: [], prefix: prefix))
        #expect(Exclusions.unreadable.excludes(formula, apps: [], prefix: prefix), "a list that cannot be read keeps everything")
        #expect(Exclusions.notYetRead.excludes(formula, apps: [], prefix: prefix), "a list not read yet keeps everything")

        let unrelated = Exclusions(paths: [URL(filePath: "/Applications/Other.app")], bundleIdentifiers: ["com.other.app"])
        #expect(!unrelated.excludes(cask, apps: [app], prefix: prefix))
        #expect(!unrelated.excludes(formula, apps: [], prefix: prefix))
        #expect(!Exclusions(paths: [URL(filePath: "/opt/homebrew/Cellar/curl")]).excludes(formula, apps: [], prefix: prefix))
    }

    @Test func matchesAppsByBundleIdentifierOrPlace() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")

        #expect(Exclusions(bundleIdentifiers: ["com.example.app"]).excludes(app))
        #expect(Exclusions(paths: [URL(filePath: "/Applications/Example.app")]).excludes(app))
        #expect(!Exclusions(bundleIdentifiers: ["com.other.app"]).excludes(app))
    }

    /// `/var` is a symbolic link to `/private/var`. Written either way it is the same file, and an exclusion
    /// that only held for one spelling would quietly stop protecting anything under `/var`, `/tmp`, or `/etc`.
    @Test func holdsHoweverTheSamePathIsSpelled() {
        let exclusions = Exclusions(paths: [URL(filePath: "/var/folders/x/C/com.example.app")])

        #expect(exclusions.excludes(URL(filePath: "/private/var/folders/x/C/com.example.app")))
        #expect(exclusions.excludes(URL(filePath: "/private/var/folders/x/C/com.example.app/inside")))
        #expect(!exclusions.excludes(URL(filePath: "/private/var/folders/x/C/com.example.other")))

        let theOtherWayRound = Exclusions(paths: [URL(filePath: "/private/tmp/keep")])
        #expect(theOtherWayRound.excludes(URL(filePath: "/tmp/keep")))
    }

    /// The other direction: a folder around something excluded, however either of them is spelled.
    @Test func knowsAFolderThatHoldsSomethingExcluded() {
        let exclusions = Exclusions(paths: [URL(filePath: "/var/folders/x/C/Keep/Inner/data.db")])

        #expect(exclusions.holds(URL(filePath: "/private/var/folders/x/C/Keep")))
        #expect(exclusions.holds(URL(filePath: "/VAR/folders/x/C/keep/inner", directoryHint: .isDirectory)))
        #expect(!exclusions.holds(URL(filePath: "/var/folders/x/C/Keep/Inner/data.db")))
        #expect(!exclusions.holds(URL(filePath: "/var/folders/x/C/Kee")))
        #expect(!exclusions.holds(URL(filePath: "/var/folders/x/C/Other")))
        #expect(!Exclusions.none.holds(URL(filePath: "/var")))
    }

    @Test func refusesToRemoveAFolderThatHoldsSomethingExcluded() async throws {
        let directory = try TemporaryDirectory()
        let kept = try directory.file("home/Library/Application Support/Example/keep.db")
        try directory.file("home/Library/Application Support/Example/cache.db")
        let folder = kept.deletingLastPathComponent()
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))
        let trash = try directory.directory("Trash")
        let service = TrashService(environment: environment, exclusions: Exclusions(paths: [kept])) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let result = await service.trash([folder])
        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.protectedLocation])
        #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
    }

    @Test func keepsExcludedItemsOutOfResults() {
        let urls = [URL(filePath: "/a/one"), URL(filePath: "/a/two"), URL(filePath: "/b/three")]
        let kept = Exclusions(paths: [URL(filePath: "/a")]).keeping(urls) { $0 }
        #expect(kept == [URL(filePath: "/b/three")])
    }

    @Test func survivesBeingWrittenAndReadBack() async throws {
        let directory = try TemporaryDirectory()
        let store = ExclusionStore(url: directory.url.appending(path: "exclusions.json"))
        #expect(await store.load() == .none)

        let exclusions = Exclusions(paths: [URL(filePath: "/Users/x/Keep")], bundleIdentifiers: ["com.example.app"])
        await store.save(exclusions)
        #expect(await store.load() == exclusions)
    }

    /// The app reads the list at launch, and `peel exclusions` can change it while the app runs. A change reads the
    /// list again under the file's lock, so what the other one saved meanwhile is kept.
    @Test func aChangeKeepsWhatAnotherWriterSaved() async throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "Peel/exclusions.json")
        let (app, terminal) = (ExclusionStore(url: file), ExclusionStore(url: file))
        let (kept, added) = (URL(filePath: "/Users/x/Kept"), URL(filePath: "/Users/x/Added"))
        _ = await app.load()
        await terminal.save(Exclusions(paths: [kept]))

        let outcome = await app.change { $0.paths.insert(added) }

        #expect(outcome == .saved(Exclusions(paths: [kept, added])))
        #expect(await app.load().paths == [kept, added])
    }

    /// Changes made at once, as two processes can make them, each land.
    @Test func changesMadeAtOnceAllLand() async throws {
        let directory = try TemporaryDirectory()
        let store = ExclusionStore(url: directory.url.appending(path: "Peel/exclusions.json"))

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask { _ = await store.change { $0.paths.insert(URL(filePath: "/Users/x/\(index)")) } }
            }
        }

        #expect(await store.load().paths.count == 16)
    }

    /// A list that cannot be read is left as it is: changing it would throw away what the user chose.
    @Test func aChangeLeavesAListItCannotReadAsItIs() async throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("exclusions.json", contents: Data("not json".utf8))

        let outcome = await ExclusionStore(url: file).change { $0.bundleIdentifiers.insert("com.example.app") }

        #expect(outcome == .unreadable)
        #expect(try String(contentsOf: file, encoding: .utf8) == "not json")
    }

    /// An edit in Settings to a list that cannot be read starts a new list, as Settings says it does, and the old
    /// file stays beside it under another name.
    @Test func anEditThatStartsOverKeepsTheListItCannotReadAside() async throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("exclusions.json", contents: Data("not json".utf8))

        let outcome = await ExclusionStore(url: file).change(startingOverIfUnreadable: true) {
            $0.bundleIdentifiers.insert("com.example.app")
        }

        #expect(outcome == .saved(Exclusions(bundleIdentifiers: ["com.example.app"])))
        #expect(await ExclusionStore(url: file).load() == Exclusions(bundleIdentifiers: ["com.example.app"]))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false))
        let aside = try #require(names.first { $0.hasPrefix("exclusions-damaged-") })
        #expect(try String(contentsOf: directory.url.appending(path: aside), encoding: .utf8) == "not json")
    }

    /// A change that cannot be written says what the list would have been, so the app can keep it until it quits.
    @Test(.permissionsHold) func aChangeThatCannotBeWrittenSaysWhatItWouldHaveSaved() async throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url.appending(path: "Peel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ExclusionStore(url: folder.appending(path: "exclusions.json"))
        await store.save(Exclusions(paths: [URL(filePath: "/Users/x/Kept")]))
        try directory.setPermissions(0o500, of: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path(percentEncoded: false)) }

        let outcome = await store.change { $0.paths.insert(URL(filePath: "/Users/x/Added")) }

        #expect(outcome == .notSaved(Exclusions(paths: [URL(filePath: "/Users/x/Kept"), URL(filePath: "/Users/x/Added")])))
        #expect(await store.load().paths == [URL(filePath: "/Users/x/Kept")])
    }

    /// An entry that makes no sense is dropped, and the rest of the list is kept.
    @Test func keepsTheRestOfAListWithABadEntry() async throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("exclusions.json", contents: Data(#"{"paths":["file:///Users/x/Vault/",7,""],"bundleIdentifiers":["com.example.app",false]}"#.utf8))

        let loaded = await ExclusionStore(url: file).load()

        #expect(!loaded.isUnreadable)
        #expect(loaded.excludes(URL(filePath: "/Users/x/Vault/secret.txt")))
        #expect(loaded.bundleIdentifiers == ["com.example.app"])
    }

    /// A list that is there and cannot be read is not an empty list: what was excluded is unknown.
    @Test(.permissionsHold) func doesNotReadAListItCannotUnderstandAsEmpty() async throws {
        let directory = try TemporaryDirectory()
        let broken = try directory.file("broken.json", contents: Data(#"{"paths":["file:///Users/x/Vault/""#.utf8))
        let locked = try directory.file("locked.json", contents: Data(#"{"paths":[]}"#.utf8))
        try directory.setPermissions(0, of: "locked.json")
        defer { try? directory.setPermissions(0o644, of: "locked.json") }

        #expect(await ExclusionStore(url: broken).load().isUnreadable)
        #expect(await ExclusionStore(url: locked).load().isUnreadable)
        #expect(await ExclusionStore(url: directory.url.appending(path: "missing.json")).load() == .none)
    }

    @Test func movesNothingWhileTheListCannotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let item = try directory.file("home/Library/Caches/com.example.app/cache.db").deletingLastPathComponent()
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))
        let service = TrashService(environment: environment, exclusions: .unreadable) { $0 }

        let result = await service.trash([item])
        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.protectedLocation])
    }

    /// A list Peel cannot reach is not known to be empty: a folder on the way that cannot be searched, or a link
    /// that leads nowhere, reads as a list that cannot be read, so nothing moves.
    @Test func aListItCannotReachIsUnreadableNotEmpty() async throws {
        let directory = try TemporaryDirectory()
        let saved = Data(#"{"paths":[],"bundleIdentifiers":["com.example.app"]}"#.utf8)
        let file = try directory.file("Peel/exclusions.json", contents: saved)
        let link = directory.url.appending(path: "linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(filePath: "/nowhere/list.json"))
        try directory.setPermissions(0o600, of: "Peel")
        defer { try? directory.setPermissions(0o755, of: "Peel") }

        #expect(await ExclusionStore(url: file).load().isUnreadable)
        #expect(await ExclusionStore(url: link).load().isUnreadable)
    }

    /// Until the app has read the saved list, what the user excluded is not known, so nothing moves, as for a list
    /// that cannot be read.
    @Test func movesNothingBeforeTheListIsRead() async throws {
        let directory = try TemporaryDirectory()
        let item = try directory.file("home/Library/Caches/com.example.app/cache.db").deletingLastPathComponent()
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))
        let service = TrashService(environment: environment, exclusions: .notYetRead) { $0 }

        let result = await service.trash([item])
        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.protectedLocation])
        #expect(!Exclusions.notYetRead.isKnown && !Exclusions.notYetRead.isUnreadable)
        #expect(Exclusions.none.isKnown && !Exclusions.unreadable.isKnown)
    }

    /// Saving over a list that could not be read keeps it under another name instead of erasing it.
    @Test func keepsAListItCouldNotReadWhenANewOneIsSaved() async throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("exclusions.json", contents: Data("not json".utf8))
        let store = ExclusionStore(url: file)

        #expect(await store.save(Exclusions(bundleIdentifiers: ["com.example.app"])))

        #expect(await store.load().bundleIdentifiers == ["com.example.app"])
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false)).filter { $0.contains("damaged") }
        #expect(kept.count == 1)
        #expect(try String(contentsOf: directory.url.appending(path: try #require(kept.first)), encoding: .utf8) == "not json")
    }

    @Test func refusesToRemoveAnExcludedItem() async throws {
        let directory = try TemporaryDirectory()
        let kept = try directory.file("home/Library/Caches/com.example.keep/cache.db").deletingLastPathComponent()
        let removable = try directory.file("home/Library/Caches/com.example.other/cache.db").deletingLastPathComponent()
        let environment = SearchEnvironment(homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root"))
        let trash = try directory.directory("Trash")
        let service = TrashService(environment: environment, exclusions: Exclusions(paths: [kept])) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let result = await service.trash([kept, removable])
        #expect(result.trashed.map(\.originalURL) == [removable])
        #expect(result.failures.map(\.reason) == [.protectedLocation])
        #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
    }
}

/// Every scanner leaves out what the user excluded, so an excluded item never shows up at all.
struct ExclusionsReachEveryScannerTests {
    private func environment(in directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
    }

    @Test func aBackgroundItemTheUserExcludedIsNotListed() async throws {
        let directory = try TemporaryDirectory()
        let plist = try directory.file("home/Library/LaunchAgents/com.example.keepme.plist", contents: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Label</key><string>com.example.keepme</string></dict></plist>
        """.utf8))

        let listed = await BackgroundItems.scan(environment: environment(in: directory))
        let kept = await BackgroundItems.scan(environment: environment(in: directory), exclusions: Exclusions(paths: [plist]))

        #expect(listed.contains { $0.label == "com.example.keepme" })
        #expect(!kept.contains { $0.label == "com.example.keepme" }, "the scanner spells the path with /private and the exclusion does not")
    }

    /// An app's page lists the files its installer receipt names, and leaves out any path the user excluded.
    @Test func theItemsOfAnExcludedPathAreNotListedForAPackage() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let app = PathPattern.canonical(try directory.directory("Applications/Example.app"))
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--file-info-plist": PkgutilAnswer.fileInfo(arguments[1], packages: "com.example.pkg")
            case "--pkg-info-plist": info
            case "--files": "Applications/Example.app\n"
            default: ""
            }
        }

        let listed = await PackageReceipts.receipts(installing: app, exclusions: .none, pkgutil: pkgutil)
        let excluded = await PackageReceipts.receipts(installing: app, exclusions: Exclusions(paths: [app]), pkgutil: pkgutil)

        #expect(listed.first?.items.count == 1)
        #expect(excluded.first?.items.isEmpty == true)
    }

    /// A leftover folder around something excluded is shown and says why, but is never selected.
    @Test func aLeftoverThatHoldsSomethingExcludedIsShownAndLeftAlone() async throws {
        let directory = try TemporaryDirectory()
        let kept = try directory.file("home/Library/Application Support/com.example.app/keep.db")
        try directory.file("home/Library/Caches/com.example.app/cache.db")
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")

        let plan = await Uninstallation.prepare(app, installedApps: [app], exclusions: Exclusions(paths: [kept]), environment: environment(in: directory))

        let holder = try #require(plan.scan.leftovers.first { $0.url.lastPathComponent == "com.example.app" && $0.kind == .applicationSupport })
        #expect(holder.match.heldBack == .holdsAnExclusion)
        #expect(!holder.match.isRecommended)
        let suggested = plan.suggestedSelection(canUseHelper: true).map { $0.path(percentEncoded: false) }
        #expect(!suggested.contains { $0.contains("Application Support") })
        #expect(suggested.contains { $0.contains("/Caches/com.example.app") })
    }

    /// Developer caches and build artifacts leave out a folder that holds something excluded.
    @Test func aCacheOrAnArtifactThatHoldsSomethingExcludedIsNotOffered() async throws {
        let directory = try TemporaryDirectory()
        let keptInCache = try directory.file("home/Library/Caches/pip/http/keep.bin", bytes: 4096)
        try directory.file("home/Projects/app/package.json")
        let keptInModules = try directory.file("home/Projects/app/node_modules/patched/index.js", bytes: 4096)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let exclusions = Exclusions(paths: [keptInCache, keptInModules])

        let caches = await DeveloperCaches.scan(
            in: SearchEnvironment(homeDirectory: home, rootDirectory: home), exclusions: exclusions
        )
        #expect(!caches.flatMap(\.locations).contains { $0.url.lastPathComponent == "pip" })

        let artifacts = await ProjectArtifacts.scan(roots: [home.appending(path: "Projects")], exclusions: exclusions).artifacts
        #expect(artifacts.isEmpty)
    }

    /// An app excluded by identifier takes its background items with it: they are not listed, so not stopped.
    @Test func theBackgroundItemsOfAnExcludedAppAreNotListed() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/LaunchAgents/com.example.keepme.updater.plist", contents: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Label</key><string>com.example.keepme.updater</string></dict></plist>
        """.utf8))
        let app = InstalledApp(url: URL(filePath: "/Applications/Keep Me.app"), bundleIdentifier: "com.example.KeepMe", name: "Keep Me")

        let listed = await BackgroundItems.scan(installedApps: [app], environment: environment(in: directory))
        let kept = await BackgroundItems.scan(
            installedApps: [app],
            environment: environment(in: directory),
            exclusions: Exclusions(bundleIdentifiers: ["com.example.KeepMe"])
        )

        #expect(listed.first { $0.label == "com.example.keepme.updater" }?.ownerBundleIdentifier == "com.example.KeepMe")
        #expect(!kept.contains { $0.label == "com.example.keepme.updater" })
    }

    @Test func aPluginTheUserExcludedIsNotListed() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/QuickLook/Keep.qlgenerator/Contents/Info.plist", contents: Data("<plist/>".utf8))
        let plugin = directory.url.appending(path: "home/Library/QuickLook/Keep.qlgenerator")

        let listed = await Plugins.scan(environment: environment(in: directory))
        let kept = await Plugins.scan(environment: environment(in: directory), exclusions: Exclusions(paths: [plugin]))

        #expect(listed.contains { $0.url.lastPathComponent == "Keep.qlgenerator" })
        #expect(!kept.contains { $0.url.lastPathComponent == "Keep.qlgenerator" }, "the scanner spells the path with /private and the exclusion does not")
    }

    /// A stand-in for `pkgutil` says what is installed, so the test does not depend on the receipts of the Mac
    /// running it.
    @Test func aReceiptItemTheUserExcludedIsNotListed() async throws {
        let directory = try TemporaryDirectory()
        let volume = PathPattern.canonical(directory.url).path(percentEncoded: false)
        let app = PathPattern.canonical(try directory.directory("Applications/Example.app"))
        let support = PathPattern.canonical(try directory.directory("Library/Application Support/Example"))
        let info = try #require(String(
            data: PropertyListSerialization.data(fromPropertyList: ["volume": volume, "install-location": ""], format: .xml, options: 0),
            encoding: .utf8
        ))
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages("com.example.pkg")
            case "--pkg-info-plist": info
            case "--files": "Applications/Example.app\nLibrary/Application Support/Example\n"
            default: ""
            }
        }

        let all = await PackageReceipts.list(exclusions: .none, pkgutil: pkgutil).receipts
        #expect(Set(all.flatMap(\.items).map(\.url)) == [app, support])

        let kept = await PackageReceipts.list(exclusions: Exclusions(paths: [support]), pkgutil: pkgutil).receipts
        #expect(kept.flatMap(\.items).map(\.url) == [app])
    }

    /// Excluding a whole disk, a home folder, or a Library would leave every tool with nothing to show. Settings
    /// and `peel exclusions add` share this one rule, so they refuse the same paths.
    @Test func refusesAnExclusionTooBroadToBeWorthAnything() {
        let home = URL(filePath: "/Users/me")
        for path in ["/", "/Users/me", "/Users/me/", "/Users/me/Library", "/Applications", "/Library", "/System", "/Users", "/Volumes", "/opt"] {
            #expect(Exclusions.isTooBroad(URL(filePath: path), home: home), "\(path) was allowed")
        }
        // Matching folds case and reads a path name by name, so the same folders written otherwise are as broad.
        for path in ["/users/me", "/USERS/ME/library", "/Users/me/./Library", "/Users/me/Documents/../Library", "/library"] {
            #expect(Exclusions.isTooBroad(URL(filePath: path), home: home), "\(path) was allowed")
        }
        for path in ["/Users/me/Documents/Keep", "/Users/me/Library/Application Support/Acme", "/Applications/Acme.app", "/Volumes/Work/Acme"] {
            #expect(!Exclusions.isTooBroad(URL(filePath: path), home: home), "\(path) was refused")
        }
    }
}
