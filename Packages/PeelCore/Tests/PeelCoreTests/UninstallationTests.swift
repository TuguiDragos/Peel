import Foundation
@testable import PeelCore
import Testing

struct UninstallationTests {
    private let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")

    private func leftover(
        _ name: String,
        confidence: MatchConfidence = .certain,
        sharedWith: [String] = [],
        requiresPrivileges: Bool = false
    ) -> Leftover {
        Leftover(
            url: URL(filePath: "/Users/me/Library/Caches/\(name)"),
            kind: .caches,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: confidence, sharedWith: sharedWith),
            size: 1_000,
            isMeasured: true,
            requiresPrivileges: requiresPrivileges
        )
    }

    private func uninstallation(
        app: InstalledApp? = nil,
        appRequiresPrivileges: Bool = false,
        leftovers: [Leftover]
    ) -> Uninstallation {
        Uninstallation(
            app: app ?? self.app,
            appSize: 10_000,
            appRequiresPrivileges: appRequiresPrivileges,
            scan: LeftoverScan(leftovers: leftovers, unreadableLocations: [])
        )
    }

    /// When an app removes itself, nobody reviews a list first, so a match on its name is not enough. Only what
    /// is certainly its own or named inside its own identifier goes, and nothing that needs the helper. If the
    /// app itself needs the helper, nothing goes at all.
    @Test func takesOnlyWhatIsCertainWhenNobodyReviewsTheList() {
        let own = leftover("com.example.app")
        let named = leftover("Example", confidence: .likely)
        let shared = leftover("shared", sharedWith: ["com.example.other"])
        let rootOwned = leftover("daemon.plist", requiresPrivileges: true)
        let tool = leftover("com.example.App.CLI", confidence: .likely)
        let sharedTool = leftover("com.example.app.Sync", confidence: .likely, sharedWith: ["com.example.other"])
        let plan = uninstallation(leftovers: [own, named, shared, rootOwned, tool, sharedTool])

        #expect(plan.unreviewedSelection == [app.url, own.url, tool.url])
        #expect(uninstallation(appRequiresPrivileges: true, leftovers: [own]).unreviewedSelection.isEmpty)
    }

    /// Remove Peel hands the helper the app's own links in a folder only an administrator can change, and nothing
    /// else that needs the helper.
    @Test func handsTheHelperOnlyItsOwnLinksWhenNobodyReviewsTheList() {
        func link(_ name: String, sharedWith: [String] = []) -> Leftover {
            Leftover(
                url: URL(filePath: "/usr/local/bin/\(name)"),
                kind: .commandLineTools,
                match: LeftoverMatch(reason: .linksToTheApp, confidence: .certain, sharedWith: sharedWith),
                size: 0,
                isMeasured: true,
                requiresPrivileges: true
            )
        }
        let tool = link("example")
        let shared = link("shared", sharedWith: ["com.example.other"])
        let daemon = leftover("daemon.plist", requiresPrivileges: true)
        let plan = uninstallation(leftovers: [tool, shared, daemon])

        #expect(plan.unreviewedLinks == [tool.url])
        #expect(!plan.unreviewedSelection.contains(tool.url))
        #expect(uninstallation(appRequiresPrivileges: true, leftovers: [tool]).unreviewedLinks.isEmpty)
    }

    @Test func selectsTheAppAndRecommendedLeftovers() {
        let recommended = leftover("recommended")
        let shared = leftover("shared", sharedWith: ["com.example.other"])
        let possible = leftover("possible", confidence: .possible)
        let privileged = leftover("privileged", requiresPrivileges: true)
        let plan = uninstallation(leftovers: [recommended, shared, possible, privileged])

        #expect(plan.suggestedSelection(canUseHelper: false) == [app.url, recommended.url])
        #expect(plan.suggestedSelection(canUseHelper: true) == [app.url, recommended.url, privileged.url])
        #expect(plan.privilegedURLs == [privileged.url])
    }

    @Test func leavesProtectedAndPrivilegedAppsAlone() {
        let protectedApp = InstalledApp(url: URL(filePath: "/System/Applications/Chess.app"), bundleIdentifier: "com.apple.Chess", name: "Chess", isSystemProtected: true)

        #expect(uninstallation(app: protectedApp, leftovers: []).suggestedSelection(canUseHelper: true).isEmpty)
        // An app macOS keeps stays, so what it holds is data in use, not a leftover. For Notes, that is every note.
        #expect(
            uninstallation(app: protectedApp, leftovers: [leftover("com.apple.Chess")]).suggestedSelection(
                canUseHelper: true
            ).isEmpty
        )
        #expect(
            uninstallation(appRequiresPrivileges: true, leftovers: []).suggestedSelection(canUseHelper: false).isEmpty
        )
        #expect(
            uninstallation(appRequiresPrivileges: true, leftovers: []).suggestedSelection(canUseHelper: true) == [
                app.url
            ]
        )
        #expect(uninstallation(appRequiresPrivileges: true, leftovers: []).privilegedURLs == [app.url])
    }

    /// A checkbox can select what a row lets the person choose: nothing Peel leaves alone or with something
    /// excluded inside, nothing that needs the helper while it cannot act, and nothing of an app the person excluded
    /// or of Peel. Everything Peel suggests is among it.
    @Test func selectsOnlyWhatARowLetsThePersonChoose() {
        let plain = leftover("plain")
        let possible = leftover("possible", confidence: .possible)
        let keys = leftover("keys").heldBack(.holdsKeys)
        let excluded = leftover("excluded").heldBack(.holdsAnExclusion)
        let unmeasured = leftover("unmeasured").heldBack(.notMeasured)
        let privileged = leftover("privileged", requiresPrivileges: true)
        let plan = uninstallation(leftovers: [plain, possible, keys, excluded, unmeasured, privileged])

        #expect(plan.selectable(canUseHelper: false) == [app.url, plain.url, possible.url, unmeasured.url])
        #expect(
            plan.selectable(canUseHelper: true) == [app.url, plain.url, possible.url, unmeasured.url, privileged.url]
        )
        for canUseHelper in [false, true] {
            #expect(
                plan.suggestedSelection(canUseHelper: canUseHelper)
                    .isSubset(of: plan.selectable(canUseHelper: canUseHelper))
            )
        }

        let needsHelper = uninstallation(appRequiresPrivileges: true, leftovers: [plain])
        #expect(needsHelper.selectable(canUseHelper: false) == [plain.url])
        #expect(needsHelper.selectable(canUseHelper: true) == [app.url, plain.url])
        var beyond = needsHelper
        beyond.isAppBeyondTheHelper = true
        #expect(beyond.selectable(canUseHelper: true) == [plain.url])

        let protectedApp = InstalledApp(url: URL(filePath: "/System/Applications/Chess.app"), bundleIdentifier: "com.apple.Chess", name: "Chess", isSystemProtected: true)
        #expect(uninstallation(app: protectedApp, leftovers: [plain]).selectable(canUseHelper: true) == [plain.url])

        var excludedApp = uninstallation(leftovers: [plain])
        excludedApp.isExcluded = true
        #expect(excludedApp.selectable(canUseHelper: true).isEmpty)

        let peel = InstalledApp(url: URL(filePath: "/Applications/Peel.app"), bundleIdentifier: "com.tuguidragos.Peel", name: "Peel")
        #expect(uninstallation(app: peel, leftovers: [plain]).selectable(canUseHelper: true).isEmpty)
    }

    /// An app that would stay gets nothing selected, as an app macOS keeps does: its leftovers would go first
    /// and leave it without its settings. It stays when the helper may not move it, or when it needs the helper
    /// and the helper is not there. In a batch, what such an app shares with another chosen app stays too.
    @Test func anAppThatWouldStayGetsNothingSelected() {
        let own = leftover("com.example.app")
        let needsHelper = uninstallation(appRequiresPrivileges: true, leftovers: [own])
        var beyond = needsHelper
        beyond.isAppBeyondTheHelper = true

        #expect(needsHelper.suggestedSelection(canUseHelper: false).isEmpty, "the helper is not there to move the app")
        #expect(needsHelper.suggestedSelection(canUseHelper: true) == [app.url, own.url])
        #expect(beyond.suggestedSelection(canUseHelper: true).isEmpty, "the helper may not move the app")

        let other = InstalledApp(url: URL(filePath: "/Applications/Other.app"), bundleIdentifier: "com.example.other", name: "Other")
        let shared = leftover("shared", sharedWith: [other.bundleIdentifier])
        let otherPlan = Uninstallation(
            app: other, appSize: 10_000, appRequiresPrivileges: false,
            scan: LeftoverScan(
                leftovers: [leftover("com.example.other"), leftover("shared", sharedWith: [app.bundleIdentifier])],
                unreadableLocations: []
            )
        )
        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(appRequiresPrivileges: true, leftovers: [own, shared]), otherPlan,
        ])

        #expect(bulk.suggestedSelection(canUseHelper: false) == [other.url, URL(filePath: "/Users/me/Library/Caches/com.example.other")])
        #expect(bulk.suggestedSelection(canUseHelper: true).isSuperset(of: [app.url, own.url, shared.url, other.url]))
    }

    @Test func removePeelTakesItsFilesWhateverOtherCopyOfPeelIsKnown() {
        let peel = InstalledApp(url: URL(filePath: "/Applications/Peel.app"), bundleIdentifier: "com.tuguidragos.Peel", name: "Peel")
        func file(_ name: String, sharedWith apps: [String] = [], heldBack: HoldBack? = nil) -> Leftover {
            Leftover(
                url: URL(filePath: "/Users/me/Library/Preferences/\(name)"),
                kind: .preferences,
                match: LeftoverMatch(
                    reason: .bundleIdentifier, confidence: .certain, sharedWith: apps,
                    otherCopies: [URL(filePath: "/Volumes/Peel/Peel.app")], heldBack: heldBack
                ),
                size: 1_000,
                isMeasured: true,
                requiresPrivileges: false
            )
        }
        let settings = file("com.tuguidragos.Peel.plist")
        let shared = file("com.tuguidragos.shared.plist", sharedWith: ["com.example.other"])
        let container = file("com.tuguidragos.Peel.box", heldBack: .holdsDocuments)
        let plan = uninstallation(app: peel, leftovers: [settings, shared, container])

        #expect(plan.unreviewedSelection == [peel.url, settings.url])
    }

    /// Peel is removed only from its own Settings, where its helper and login item go first. Its page lists its
    /// files, but nothing of it can be selected or moved there, alone or among other apps. Remove Peel still takes
    /// what is certainly its own.
    @Test func peelIsRemovedOnlyFromItsOwnSettings() {
        let peel = InstalledApp(url: URL(filePath: "/Applications/Peel.app"), bundleIdentifier: "com.tuguidragos.Peel", name: "Peel")
        let own = leftover("com.tuguidragos.Peel")
        let plan = uninstallation(app: peel, leftovers: [own])

        #expect(plan.isPeel)
        #expect(plan.suggestedSelection(canUseHelper: true).isEmpty)
        #expect(plan.removalOrder(of: [peel.url, own.url]).isEmpty)
        #expect(plan.movable(among: [own], withApp: true).count == 0)
        #expect(plan.privilegedURLs.isEmpty)
        #expect(plan.unreviewedSelection == [peel.url, own.url], "Remove Peel no longer takes what is Peel's")

        let example = leftover("com.example.app")
        let bulk = BulkUninstallation(uninstallations: [plan, uninstallation(leftovers: [example])])
        #expect(bulk.suggestedSelection(canUseHelper: true) == [app.url, example.url])
        #expect(bulk.removalOrder(of: [peel.url, own.url, app.url, example.url]) == [app.url, example.url])
        #expect(Set(bulk.items.filter(\.isPeels).map(\.url)) == [peel.url, own.url])
        #expect(bulk.total.known == 11_000, "Peel's files were counted as something to remove")
    }

    /// An app the helper may not move would stay, and so would everything of its own, so it is never offered.
    /// Neither is an app macOS keeps, wherever it sits.
    @Test(.permissionsHold) func anAppTheHelperMayNotMoveIsNeverOffered() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/Applications/Scribbler.app/Contents/Info.plist", bytes: 4_096)
        try directory.file("root/Volumes/Other/Applications/Scribbler.app/Contents/Info.plist", bytes: 4_096)
        let inReach = directory.url.appending(path: "root/Applications/Scribbler.app")
        let beyond = directory.url.appending(path: "root/Volumes/Other/Applications/Scribbler.app")
        for bundle in [inReach, beyond] {
            try directory.setPermissions(0o555, of: bundle)
        }
        defer {
            for bundle in [inReach, beyond] {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: bundle.path(percentEncoded: false)
                )
            }
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        for (bundle, isBeyond) in [(inReach, false), (beyond, true)] {
            for isKept in [false, true] {
                let app = InstalledApp(url: bundle, bundleIdentifier: "com.example.scribbler", name: "Scribbler", isSystemProtected: isKept)
                let plan = await Uninstallation.prepare(app, installedApps: [app], environment: environment)
                let bulk = BulkUninstallation(uninstallations: [plan])
                let item = try #require(bulk.items.first { $0.isApplication })
                let isOffered = !isBeyond && !isKept

                #expect(plan.appRequiresPrivileges)
                #expect(plan.isAppBeyondTheHelper == (isBeyond && !isKept))
                #expect(plan.suggestedSelection(canUseHelper: true).contains(app.url) == isOffered)
                #expect(plan.privilegedURLs.contains(app.url) == isOffered)
                #expect(plan.movable(among: [], withApp: true).count == (isOffered ? 1 : 0))
                #expect(item.isBeyondTheHelper == (isBeyond && !isKept))
                #expect(bulk.suggestedSelection(canUseHelper: true).contains(app.url) == isOffered)
                #expect(bulk.privilegedURLs.contains(app.url) == isOffered)
                #expect((bulk.total.known > 0) == isOffered)
            }
        }
    }

    /// Section headers count by the same rule as the page's total, so they add up to it. A row Peel leaves
    /// alone is listed but not counted.
    @Test func aHeaderCountsWhatCouldGoAsTheTotalDoes() {
        let own = leftover("com.example.app")
        let named = leftover("Example").heldBack(.namedLikeTheApp)
        let slow = Leftover(
            url: URL(filePath: "/Users/me/Library/Caches/slow"),
            kind: .caches,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: [])
                .forReview(.notMeasured),
            size: 0,
            isMeasured: false,
            requiresPrivileges: false
        )
        let beyond = leftover("vendor", requiresPrivileges: true).heldBack(.beyondTheHelper)
        let excluded = leftover("kept").heldBack(.holdsAnExclusion)
        let documents = leftover("container").heldBack(.holdsDocuments)
        let plan = uninstallation(leftovers: [own, named, slow, beyond, excluded, documents])

        let recommended = plan.movable(among: plan.scan.leftovers.filter(\.match.isRecommended), withApp: true)
        let review = plan.movable(among: plan.scan.leftovers.filter { !$0.match.isRecommended }, withApp: false)
        let total = plan.movable(among: plan.scan.leftovers, withApp: true)

        #expect(recommended.count == 2)
        #expect(recommended.size == SizeTotal(known: 11_000, isComplete: true))
        #expect(review.count == 2, "a row that cannot go was counted")
        #expect(review.size == SizeTotal(known: 1_000, isComplete: false))
        #expect(total.count == recommended.count + review.count)
        #expect(total.size == SizeTotal(known: recommended.size.known + review.size.known, isComplete: false))
    }

    /// A Homebrew cask can name a folder inside one the scan found, such as Steam's bundle inside its Application
    /// Support folder: both are listed, and the bytes they share are counted once.
    @Test func theTotalCountsARowInsideAnotherRowOnce() {
        let plan = uninstallation(leftovers: [leftover("Steam"), leftover("Steam/Steam.AppBundle")])

        let total = plan.movable(among: plan.scan.leftovers, withApp: false)
        #expect(total.size == SizeTotal(known: 1_000, isComplete: true))
    }

    /// An app bundle macOS will not let Peel read has no known size: its row reads "Unknown", never zero.
    @Test(.permissionsHold) func anAppBundleThatCannotBeReadIsNotMeasured() async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let bundle = try directory.directory("home/Applications/Example.app")
        try directory.file("home/Applications/Example.app/Contents/Info.plist", bytes: 4_096)
        try directory.setPermissions(0, of: "home/Applications/Example.app")
        defer { try? directory.setPermissions(0o755, of: "home/Applications/Example.app") }
        let installed = InstalledApp(url: bundle, bundleIdentifier: "com.example.app", name: "Example")
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))

        let plan = await Uninstallation.prepare(installed, installedApps: [installed], environment: environment)

        #expect(!plan.isAppMeasured, "an app that could not be read counted as measured, at zero bytes")
    }

    /// A copy of an app made as an APFS clone of another, as the Finder copies on one disk, frees almost nothing while
    /// the other is there, though it takes its full size: the page says so rather than leave a small figure
    /// unexplained.
    @Test func anAppThatSharesItsStorageWithAnotherCopySaysSo() async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let payload = try directory.file(
            "home/.Trash/Example.app/Contents/payload.bin",
            contents: Data((0..<1_048_576).map { _ in UInt8.random(in: 0...255) })
        )
        let handle = try FileHandle(forWritingTo: payload)
        try handle.synchronize()
        try handle.close()
        let bundle = try directory.directory("home/Applications/Example.app/Contents")
            .deletingLastPathComponent()
        let clone = bundle.appending(path: "Contents/payload.bin").path(percentEncoded: false)
        #expect(clonefile(payload.path(percentEncoded: false), clone, 0) == 0)
        let installed = InstalledApp(url: bundle, bundleIdentifier: "org.example.app", name: "Example")
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))

        let plan = await Uninstallation.prepare(installed, installedApps: [installed], environment: environment)

        #expect(plan.appSharesStorage)
    }

    /// Watch the Trash leads to the page of an app already in the Trash, so what it left behind can go too. Its bundle
    /// can't move again, so it is neither selected nor counted, on its own page or among several apps, and the app
    /// does not count as one that stays, which would hold its leftovers back.
    @Test(arguments: ["home/.Trash/Example.app", "home/.Trash/Old Apps/Example.app"])
    func anAppAlreadyInTheTrashLeavesOnlyItsLeftoversToMove(place: String) async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let bundle = try directory.directory(place)
        try directory.file("\(place)/Contents/Info.plist", bytes: 4_096)
        try directory.file("home/Library/Preferences/org.example.app.plist")
        let installed = InstalledApp(url: bundle, bundleIdentifier: "org.example.app", name: "Example")
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))

        let plan = await Uninstallation.prepare(installed, installedApps: [installed], environment: environment)
        #expect(plan.isAppInTheTrash)
        #expect(plan.suggestedSelection(canUseHelper: true).map(\.lastPathComponent) == ["org.example.app.plist"])
        #expect(!plan.selectable(canUseHelper: true).contains(bundle))
        #expect(plan.movable(among: plan.scan.leftovers, withApp: true).count == 1)
        #expect(!plan.privilegedURLs.contains(bundle))

        let several = await BulkUninstallation.prepare(
            [installed],
            installedApps: [installed],
            environment: environment
        )
        #expect(several.suggestedSelection(canUseHelper: true).map(\.lastPathComponent) == ["org.example.app.plist"])
        #expect(!several.selectable(canUseHelper: true).contains(bundle))
        #expect(several.staying(selected: []).isEmpty, "an app already in the Trash held its leftovers back")
        #expect(several.total == SizeTotal(plan.scan.leftovers.map { $0.isMeasured ? $0.size : nil }))
    }

    /// Moved alone, an app inside another app's bundle would be cut out of it. It stays, on its own page and among
    /// several apps alike.
    @Test func anAppInsideAnotherAppStaysWithIt() async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "org.example.outer.inner"], format: .xml, options: 0
        )
        let bundle = try directory.directory("home/Applications/Outer.app/Contents/Applications/Inner.app")
        try directory.file("home/Applications/Outer.app/Contents/Applications/Inner.app/Contents/Info.plist", contents: info)
        try directory.file("home/Library/Preferences/org.example.outer.inner.plist")
        let installed = try #require(AppInspector.inspect(bundle))
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))

        let plan = await Uninstallation.prepare(installed, installedApps: [installed], environment: environment)
        #expect(installed.enclosingPackage?.lastPathComponent == "Outer.app")
        #expect(plan.appStays(canUseHelper: true))
        #expect(plan.suggestedSelection(canUseHelper: true).isEmpty)
        #expect(!plan.selectable(canUseHelper: true).contains(bundle))
        #expect(plan.movable(among: plan.scan.leftovers, withApp: true).count == plan.scan.leftovers.count)

        let several = await BulkUninstallation.prepare(
            [installed],
            installedApps: [installed],
            environment: environment
        )
        #expect(several.suggestedSelection(canUseHelper: true).isEmpty)
        #expect(!several.selectable(canUseHelper: true).contains(bundle))
        #expect(several.total == SizeTotal(plan.scan.leftovers.map { $0.isMeasured ? $0.size : nil }))
    }

    /// Excluded by identifier or by path, the app and everything the scan would find are left alone.
    @Test func leavesAnExcludedAppAndItsFilesAlone() async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let bundle = try directory.directory("home/Applications/Example.app")
        try directory.file("home/Library/Preferences/com.example.app.plist")
        let installed = InstalledApp(url: bundle, bundleIdentifier: "com.example.app", name: "Example")
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))

        let free = await Uninstallation.prepare(installed, installedApps: [installed], environment: environment)
        #expect(free.suggestedSelection(canUseHelper: true).count == 2)

        for exclusions in [Exclusions(bundleIdentifiers: ["com.example.app"]), Exclusions(paths: [bundle])] {
            let plan = await Uninstallation.prepare(
                installed,
                installedApps: [installed],
                exclusions: exclusions,
                environment: environment
            )
            #expect(plan.isExcluded)
            #expect(plan.scan.leftovers.isEmpty)
            #expect(plan.suggestedSelection(canUseHelper: true).isEmpty)
            #expect(plan.privilegedURLs.isEmpty)
            #expect(plan.removalOrder(of: free.suggestedSelection(canUseHelper: true)).isEmpty)
        }
    }

    /// A command-line tool's link in root's `/usr/local/bin` that leads into the app goes with it, through the
    /// helper, which takes it once the app has moved and the link leads nowhere.
    @Test(.permissionsHold) func aToolsLinkInRootsFolderGoesWithTheApp() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(url: directory.url.appending(path: "root/Applications/Scribbler.app"), bundleIdentifier: "com.example.scribbler", name: "Scribbler")
        try directory.file("root/Applications/Scribbler.app/Contents/MacOS/scribble")
        let bin = try directory.directory("root/usr/local/bin")
        let link = bin.appending(path: "scribble")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app.url.appending(path: "Contents/MacOS/scribble"))
        try directory.setPermissions(0o555, of: bin)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: bin.path(percentEncoded: false)
            )
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        let plan = await Uninstallation.prepare(app, installedApps: [app], environment: environment)
        let leftover = try #require(plan.scan.leftovers.first { $0.url.lastPathComponent == "scribble" })
        #expect(leftover.requiresPrivileges)
        #expect(leftover.match.heldBack == nil, "held back: \(String(describing: leftover.match.heldBack))")
        #expect(plan.suggestedSelection(canUseHelper: true).contains(leftover.url))
        #expect(plan.privilegedURLs.contains(leftover.url))
    }

    /// A folder the helper would refuse to move, such as root's `/Library/Developer` matched on the name of an
    /// app called Developer, is held back and cannot be selected, so it never reaches the helper to be refused.
    @Test(.permissionsHold) func whatTheHelperMayNotMoveIsNeverOffered() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(url: directory.url.appending(path: "root/Applications/Scribbler.app"), bundleIdentifier: "com.example.scribbler", name: "Scribbler")
        let served = try directory.directory("root/Library/Application Support/com.example.scribbler")
        let named = try directory.directory("root/Library/Scribbler")
        let identified = try directory.directory("root/Library/com.example.scribbler")
        for folder in [served, named, identified] {
            try directory.setPermissions(0o555, of: folder)
        }
        defer {
            for folder in [served, named, identified] {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: folder.path(percentEncoded: false)
                )
            }
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )

        let plan = await Uninstallation.prepare(app, installedApps: [app], environment: environment)
        func leftover(_ url: URL) throws -> Leftover {
            try #require(
                plan.scan.leftovers.first {
                    PathPattern.comparablePath(of: $0.url) == PathPattern.comparablePath(of: url)
                }
            )
        }
        let suggested = plan.suggestedSelection(canUseHelper: true)
        let bulk = BulkUninstallation(uninstallations: [plan])

        let inReach = try leftover(served)
        #expect(inReach.requiresPrivileges)
        #expect(inReach.match.heldBack == nil)
        #expect(suggested.contains(inReach.url))
        #expect(plan.privilegedURLs.contains(inReach.url))
        #expect(bulk.privilegedURLs.contains(inReach.url))

        for url in [named, identified] {
            let beyond = try leftover(url)
            #expect(beyond.requiresPrivileges)
            #expect(beyond.match.heldBack == .beyondTheHelper, "\(url.lastPathComponent) is \(String(describing: beyond.match.heldBack))")
            #expect(beyond.match.heldBack?.cannotBeMoved == true)
            #expect(!suggested.contains(beyond.url))
            #expect(!plan.privilegedURLs.contains(beyond.url))
            #expect(!bulk.privilegedURLs.contains(beyond.url))
            #expect(!bulk.suggestedSelection(canUseHelper: true).contains(beyond.url))
        }
    }

    /// Many casks name `/Applications/<Name>.app` among what they delete. The app's URL ends in a slash and the
    /// cask's path does not, so they are compared as paths, and the app is never listed as its own leftover.
    @Test func doesNotListTheAppAsItsOwnLeftover() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let bundle = try directory.directory("home/Applications/Example.app")
        let cache = try directory.directory("home/Library/Caches/com.example.app")
        let installed = InstalledApp(url: bundle, bundleIdentifier: "com.example.app", name: "Example")
        let path = PathPattern.comparablePath(of: bundle)
        let cask = HomebrewPackage(
            name: "example",
            kind: .cask,
            appNames: ["Example.app"],
            leftoverPatterns: [path, path + "/", PathPattern.comparablePath(of: cache) + "/"]
        )
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))

        let plan = await Uninstallation.prepare(
            installed,
            installedApps: [installed],
            casks: [cask],
            environment: environment
        )

        #expect(!plan.scan.leftovers.contains { PathPattern.comparablePath(of: $0.url) == path }, "the app is listed as its own leftover")
        #expect(plan.scan.leftovers.count { $0.url.lastPathComponent == "com.example.app" } == 1, "one folder, two rows")
    }

    /// Two locations share the home folder, one for hidden items and one for plain ones. A path belongs to the
    /// location whose rule would have found it, not to whichever comes first in the table: no single order gets
    /// both of the first two checks right.
    @Test func readsAPathByTheLocationThatWouldHaveFoundIt() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        let environment = SearchEnvironment(
            homeDirectory: home,
            rootDirectory: URL(filePath: "/", directoryHint: .isDirectory)
        )

        func place(_ path: String) -> SearchLocation.Kind {
            Uninstallation.place(of: URL(filePath: path), in: environment).kind
        }

        #expect(place("/Users/me/Postman") == .homeFolder)
        #expect(place("/Users/me/.spotify") == .hiddenHomeFiles)
        #expect(place("/Users/me/Documents/Foo") == .elsewhere)
        #expect(place("/Users/me/Postman/files") == .elsewhere)
        #expect(place("/Users/me/Library/Preferences/com.example.app.plist") == .preferences)
        #expect(place("/Users/me/Library/Thunderbird/profile") == .library)
    }

    /// A name that starts with a combining mark is read whole: split by Swift's characters, the slash before it
    /// and the mark are one, and the mark would be lost.
    @Test func readsANameThatStartsWithACombiningMarkWhole() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        let root = URL(filePath: "/", directoryHint: .isDirectory)
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: root)
        let caches = PathPattern.comparablePath(of: home.appending(path: "Library/Caches"))

        let place = Uninstallation.place(of: URL(filePath: caches + "/\u{301}Foo/cache.db"), in: environment)

        #expect(place.kind == .caches)
        #expect(place.components == ["\u{301}Foo", "cache.db"])
    }

    @Test func movesTheAppBeforeItsLeftovers() {
        let first = leftover("first")
        let second = leftover("second")
        let plan = uninstallation(leftovers: [first, second])

        #expect(plan.removalOrder(of: [app.url, second.url, first.url]) == [app.url, first.url, second.url])
        #expect(plan.removalOrder(of: [second.url]) == [second.url])
    }

    /// A service that moves into the test's own Trash and refuses `refused`, as macOS refuses an app it won't let
    /// Peel move.
    private func service(in directory: borrowing TemporaryDirectory, refusing refused: URL?) throws -> TrashService {
        let trash = try directory.directory("Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(environment: environment) { url in
            guard url != refused else { throw CocoaError(.fileWriteNoPermission) }
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    /// An app's files move only once the app has, so an app that stays keeps everything of its own.
    @Test func anAppThatStaysKeepsEverythingOfItsOwn() async throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Example.app")
        let cache = try directory.directory("home/Library/Caches/com.example.app")
        let plan = uninstallation(
            app: InstalledApp(url: bundle, bundleIdentifier: "com.example.app", name: "Example"),
            leftovers: [Leftover(
                url: cache,
                kind: .caches,
                match: LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: []),
                size: 16,
                isMeasured: true,
                requiresPrivileges: false
            )]
        )

        let stayed = await plan.move([bundle, cache], using: try service(in: directory, refusing: bundle))
        #expect(stayed.trashed.isEmpty)
        #expect(stayed.failures.map(\.url) == [bundle])
        #expect(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)), "a file moved although its app stayed")
        #expect(plan.keptItsFiles(after: stayed, selection: [bundle, cache]))
        #expect(!plan.keptItsFiles(after: stayed, selection: [bundle]))

        let went = await plan.move([bundle, cache], using: try service(in: directory, refusing: nil))
        #expect(went.trashed.map(\.originalURL) == [bundle, cache])
        #expect(went.failures.isEmpty)
        #expect(!plan.keptItsFiles(after: went, selection: [bundle, cache]))
    }

    private func file(_ url: URL, _ kind: SearchLocation.Kind) -> Leftover {
        Leftover(
            url: url,
            kind: kind,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: []),
            size: 16,
            isMeasured: true,
            requiresPrivileges: false
        )
    }

    @Test func aMakersFolderTheUninstallLeavesEmptyGoesToo() async throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Notes.app")
        let support = "home/Library/Application Support"
        let product = try directory.directory("\(support)/Example/Notes")
        try directory.file("\(support)/Example/Notes/data")
        let top = try directory.directory("\(support)/org.example.Notes")
        let help = try directory.directory("home/Library/Caches/com.apple.helpd/Generated/org.example.Notes")
        let plan = uninstallation(
            app: InstalledApp(url: bundle, bundleIdentifier: "org.example.Notes", name: "Notes"),
            leftovers: [file(product, .applicationSupport), file(top, .applicationSupport), file(help, .caches)]
        )

        let went = await plan.move([bundle, product, top, help], using: try service(in: directory, refusing: nil))

        let maker = directory.url.appending(path: "\(support)/Example")
        #expect(Set(went.trashed.map { PathPattern.comparablePath(of: $0.originalURL) })
            == Set([bundle, product, top, help, maker].map(PathPattern.comparablePath(of:))))
        let records = RemovalPart(source: "Notes", sourceKey: nil, tool: "applications")
            .records(of: went, sizes: [bundle: 4_096], batch: UUID())
        let size = { (url: URL) in
            let path = PathPattern.comparablePath(of: url)
            return records.first { PathPattern.comparablePath(of: $0.originalURL) == path }?.size
        }
        #expect(size(maker) == 0)
        #expect(size(product) == nil)
        #expect(size(bundle) == 4_096)
        #expect(!directory.url.appending(path: "home/Library/Caches/com.apple.helpd/Generated").isMissing)
        #expect(!directory.url.appending(path: support).isMissing)
        #expect(went.failures.isEmpty)
    }

    @Test func onlyAnEmptyFolderInsideALibraryLocationEverGoes() async throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Notes.app")
        let cache = try directory.directory("home/Library/Caches/org.example.Notes")
        let config = try directory.directory("home/.config/Example/org.example.Notes")
        let logs = try directory.directory("home/Library/Logs/Example/Notes")
        try directory.file("home/Library/Logs/Example/.DS_Store")
        let target = try directory.directory("home/Library/Application Support/Linked/Notes")
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "home/Library/Application Support/Example"),
            withDestinationURL: target.deletingLastPathComponent()
        )
        let throughLink = directory.url.appending(path: "home/Library/Application Support/Example/Notes")
        let app = InstalledApp(url: bundle, bundleIdentifier: "org.example.Notes", name: "Notes")
        let plan = uninstallation(app: app, leftovers: [
            file(cache, .caches), file(config, .hiddenHomeFiles), file(logs, .logs),
            file(throughLink, .applicationSupport),
        ])
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )

        let candidates = MakersFolders(environment: environment, names: plan.makersFolderNames)
            .above([cache, config, logs])
        #expect(
            candidates.map(PathPattern.comparablePath(of:))
                == [PathPattern.comparablePath(of: logs.deletingLastPathComponent())]
        )
        #expect(MakersFolders(environment: environment, names: ["caches", "library"]).above([cache]).isEmpty)

        let all = [bundle, cache, config, logs, throughLink]
        let went = await plan.move(Set(all), using: try service(in: directory, refusing: nil))

        #expect(Set(went.trashed.map { PathPattern.comparablePath(of: $0.originalURL) })
            == Set(all.map(PathPattern.comparablePath(of:))))
        let kept = [
            "home/Library/Caches", "home/.config/Example", "home/Library/Logs/Example",
            "home/Library/Application Support/Example",
        ]
        for kept in kept {
            #expect(!directory.url.appending(path: kept).isMissing, "\(kept) went")
        }
    }

    /// The receipt is what keeps macOS counting the package as installed, so it goes with the app. A receipt
    /// proves an app only up to a separator: `com.example.app2.pkg` is another package's.
    @Test func offersTheInstallerReceiptWithTheApp() async throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        for name in ["com.example.app.pkg", "com.example.app2.pkg", "com.other.thing"] {
            try directory.file("root/private/var/db/receipts/\(name).bom", bytes: 32)
            try directory.file("root/private/var/db/receipts/\(name).plist", bytes: 32)
        }

        let found = await Uninstallation.receiptLeftovers(
            for: app,
            receipts: ["com.example.app.pkg", "com.example.app2.pkg", "com.other.thing"],
            installedApps: [app],
            exclusions: .none,
            environment: environment
        )

        #expect(found.map(\.url.lastPathComponent) == ["com.example.app.pkg.bom", "com.example.app.pkg.plist"])
        #expect(found.map(\.match.reason) == [.installerReceipt, .installerReceipt])
        #expect(found.map(\.match.confidence) == [.certain, .certain])
        #expect(found.map(\.match.isRecommended) == [true, true])
        #expect(found.map(\.kind) == [.receipts, .receipts])
    }

    /// A receipt whose name begins with this app's identifier can still be another installed app's, one whose
    /// identifier carries on past the separator: `org.example.synth-fx.app.pkg` installed Synth FX, not Synth.
    @Test func leavesAReceiptToTheAppItNamesMoreClosely() async throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let receipts = ["org.example.synth.app.pkg", "org.example.synth-fx.app.pkg"]
        for name in receipts {
            try directory.file("root/private/var/db/receipts/\(name).plist", bytes: 32)
        }
        let synth = InstalledApp(
            url: URL(filePath: "/Applications/Synth.app"), bundleIdentifier: "org.example.synth", name: "Synth"
        )
        let effects = InstalledApp(
            url: URL(filePath: "/Applications/Synth FX.app"), bundleIdentifier: "org.example.synth-fx", name: "Synth FX"
        )

        let found = await Uninstallation.receiptLeftovers(
            for: synth,
            receipts: Set(receipts),
            installedApps: [synth, effects],
            exclusions: .none,
            environment: environment
        )

        #expect(found.map(\.url.lastPathComponent) == ["org.example.synth.app.pkg.plist"])
    }

    @Test func offersNoReceiptWhenNoneNamesTheApp() async throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        try directory.file("root/private/var/db/receipts/com.example.appointments.bom", bytes: 32)

        let found = await Uninstallation.receiptLeftovers(
            for: app,
            receipts: ["com.example.appointments"],
            installedApps: [app],
            exclusions: .none,
            environment: environment
        )

        #expect(found.isEmpty)
    }
}

/// Anything Peel selects on its own has to pass the guard, and the helper when it needs one, or it would be
/// offered and then refused at the last step. This suite scans every app installed on the Mac running the
/// tests, which takes minutes, so it runs only when `PEEL_TEST_THIS_MAC=1` is set. It fails when it finds no
/// app, since then nothing was checked.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PEEL_TEST_THIS_MAC"] != nil))
struct SuggestedSelectionOnThisMacTests {
    /// Every app is scanned once, and both tests share the result.
    private static let uninstallations = Task {
        let apps = await AppCatalog.installedApps()
        var plans: [Uninstallation] = []
        for app in apps {
            plans.append(await Uninstallation.prepare(app, installedApps: apps))
        }
        return plans
    }

    @Test func everythingSelectedOnThisMacMayActuallyBeRemoved() async {
        let guardian = RemovalGuard(environment: .current)
        let plans = await Self.uninstallations.value
        #expect(!plans.isEmpty, "no app was found, so nothing was checked")

        let reach = HelperReach(environment: .current)
        for uninstallation in plans {
            let app = uninstallation.app
            let needsTheHelper = Set(uninstallation.scan.leftovers.filter(\.requiresPrivileges).map(\.url))
            for url in uninstallation.suggestedSelection(canUseHelper: true) where url != app.url {
                #expect(guardian.allowsRemoval(of: url), "\(app.name): the guard refuses \(url.path(percentEncoded: false))")
                #expect(!needsTheHelper.contains(url) || !reach.isBeyond(url), "\(app.name): the helper refuses \(url.path(percentEncoded: false))")
            }
        }
    }

    /// The other half of the same rule: nothing shared with another installed app, or another copy of the app, is
    /// ever selected.
    @Test func nothingSharedWithAnotherAppIsSelected() async {
        for uninstallation in await Self.uninstallations.value {
            let app = uninstallation.app
            let suggested = uninstallation.suggestedSelection(canUseHelper: true)
            for leftover in uninstallation.scan.leftovers where suggested.contains(leftover.url) {
                let users =
                    leftover.match.sharedWith + leftover.match.otherCopies.map { $0.path(percentEncoded: false) }
                #expect(!leftover.match.isShared, "\(app.name): \(leftover.url.lastPathComponent) is shared with \(users)")
                #expect(leftover.match.confidence >= .likely, "\(app.name): \(leftover.url.lastPathComponent) is only a guess")
            }
        }
    }
}
